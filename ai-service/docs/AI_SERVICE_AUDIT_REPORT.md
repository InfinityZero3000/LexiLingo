# AI Service Audit Report

Audited by: Kaiser
Phạm vi: `ai-service/` — TRACE-CAG pipeline, KG service, STT/TTS, lexi_chat, content_etl, learner-state outbox, external TraceCAG integration API.
Ngày: 2026-08-04 · Branch: `codex/product-expansion-dev-ready`

## Tóm tắt tổng quan

- **Tổng số vấn đề:** 9 (không tính các ghi chú INFO)
- **Critical:** 0 · **High:** 1 · **Medium:** 5 · **Low:** 2 · **Info:** 1
- **Điểm nóng nhất:** `service/tracecag_service/` + `api/routes/integration_trace_cag.py` — lớp tích hợp bên ngoài mới nhất (commit `b4ce2f73`), thiết kế API sạch nhưng **dùng chung keyspace Redis conversation cache** với luồng nội bộ mà không có tenant isolation, và có cache idempotency in-memory không bao giờ được dọn.
- **Nhận định chung:** phần lớn pipeline cốt lõi (TRACE-CAG graph, STT ensemble fallback, session lifecycle, learner-state outbox, Groq key pool) đã được nối dây đúng, có test, có xử lý lỗi/fallback thực sự — không phải hàng demo. Nợ kỹ thuật thực sự tập trung ở lớp tích hợp mới, một vài chỗ quan sát/telemetry sai lệch, và một module config hoàn toàn chết song song với cơ chế thật.
- **Đề xuất fix đầu tiên:** (1) namespace lại Redis conversation-cache key theo tenant/subject trước khi bật `TRACE_CAG_EXTERNAL_ENABLED=true` ở production; (2) thay `ExternalRequestCache` in-memory bằng Redis TTL.

## Danh sách vấn đề

### High

#### 1. Rò rỉ hội thoại xuyên tenant qua key Redis `conversation:{session_id}:history` không namespace

- **Loại:** bug / business-logic (SEC + DATA)
- **Vị trí:** `ai-service/api/core/redis_client.py:310-360` (class `ConversationCache`, key `f"conversation:{session_id}:history"`), `ai-service/api/services/trace_cag/nodes_v2.py:136-150` (`_get_history` đọc theo `session_id` thô), `ai-service/api/routes/integration_trace_cag.py:52` (`session_id: str = Field(min_length=1, max_length=128)` — client bên ngoài tự chọn, không ràng buộc pattern, không gắn với `subject`).
- **Nguyên nhân gốc rễ:** `ConversationCache` là một keyspace Redis toàn cục, dùng chung bởi route nội bộ (`/chat`, `lexi_chat_service.py` — có `add_turn` ghi) và endpoint tích hợp bên ngoài mới (`/api/v1/integrations/trace-cag/v1/analyze` — chỉ đọc qua `graph.py::analyze()` → `input_node`). `session_id` do đối tác bên ngoài cung cấp không được trộn với `subject` (định danh learner) hay một prefix riêng cho traffic external. Nếu một `session_id` do đối tác chọn trùng với `session_id` đang hoạt động của một user nội bộ (TTL 2 giờ, 5 lượt gần nhất), request phân tích của đối tác sẽ đọc được nguyên văn 5 lượt hội thoại riêng tư của user đó và đưa vào ngữ cảnh sinh câu trả lời — có thể rò rỉ gián tiếp qua `tutor_response` trả về cho bên thứ ba.
- **Tác động:** vi phạm cách ly dữ liệu giữa learner nội bộ và đối tác tích hợp bên ngoài; mức độ khai thác phụ thuộc khả năng đoán/trùng `session_id` đang sống, nhưng thiết kế hiện tại không có bất kỳ rào chắn nào (không pattern, không cross-check subject).
- **Đề xuất fix:** đổi key thành `f"conversation:{tenant}:{session_id}:history"` với `tenant` lấy từ nguồn tin cậy phía server (tên service nội bộ, hoặc `subject` đã xác thực qua `verify_trace_cag_service_token`), không lấy từ input client thô; hoặc cấp hẳn một Redis DB/prefix riêng cho traffic qua `integration_trace_cag.py`.

### Medium

#### 2. Cache idempotency của endpoint tích hợp bên ngoài không bao giờ được dọn, không chia sẻ giữa các worker/replica

- **Loại:** bug / optimization (SCALE)
- **Vị trí:** `ai-service/api/services/trace_cag/external_request_cache.py:18-40` (`ExternalRequestCache`, dict in-memory), instantiate làm singleton cấp module tại `ai-service/api/routes/integration_trace_cag.py:60` (`_cache = ExternalRequestCache()`).
- **Nguyên nhân gốc rễ:** entry chỉ bị xoá khi có ai đó gọi `get()` lại với đúng `request_id` đã hết hạn (`get()` dòng 24-32) — không có background sweep, không giới hạn kích thước. Phần lớn `request_id` (theo chuẩn idempotency key) chỉ được dùng một lần rồi không bao giờ bị truy vấn lại, nên entry của nó ở lại trong RAM process vĩnh viễn. Ngoài ra cache là process-local: nếu triển khai nhiều worker/replica (hiện `Dockerfile.prod` cố định `--workers 1` để né vấn đề này, nhưng đó là ràng buộc triển khai không được ghi chú ở đâu), một request retry với cùng `X-Request-ID` bị route sang worker khác sẽ không hit cache, phá vỡ đúng bảo đảm idempotent mà endpoint quảng cáo.
- **Đề xuất fix:** chuyển sang Redis (SETNX + TTL 600s, giống toàn bộ phần còn lại của service đã dùng Redis) để có cả TTL tự động lẫn tính nhất quán multi-process/multi-replica.

#### 3. `model_used` bị gán sai trong luồng streaming của Lexi khi Groq fallback sang Gemini

- **Loại:** bug (REL/DATA — sai lệch telemetry/cache)
- **Vị trí:** `ai-service/api/services/lexi_chat_service.py:818-847` (suy luận `model_used` từ `os.getenv("GROQ_API_KEY")`), `ai-service/api/services/trace_cag/generate.py:169-317` (`stream_llm_tokens` — thử Groq trước, fallback Gemini âm thầm ở dòng 315-317, **không trả về** provider nào thực sự sinh token).
- **Nguyên nhân gốc rễ:** `stream_llm_tokens()` chỉ yield chuỗi token thô, không có tín hiệu nào cho caller biết Groq hay Gemini đã phục vụ request. `lexi_chat_service.py` sau đó đoán mù: `model_used = "groq/..." if os.getenv("GROQ_API_KEY") else "gemini-2.0-flash"`. Vì `GROQ_API_KEY` gần như luôn được cấu hình ở môi trường này, **mọi lần Groq fail/hết quota và fallback sang Gemini vẫn bị gắn nhãn "groq/..."**. Nhãn sai này được ghi vào cache response (`_write_cache_entry(..., model_used=model_used)` dòng 846) và dùng cho theo dõi/so sánh model.
- **Đề xuất fix:** để `stream_llm_tokens` trả về (qua giá trị cuối cùng của generator hoặc một out-param nhỏ) provider/model thực tế đã dùng, thay vì suy luận từ biến môi trường ở call site.

#### 4. `OptimizationConfig` là một hệ thống cấu hình chết song song với cơ chế thật

- **Loại:** dead-pipeline (CFG/DEAD)
- **Vị trí:** `ai-service/api/core/optimization_config.py` (toàn bộ file — `enable_auto_memory_management`, `qwen_timeout_ms`, `hubert_timeout_ms`, `target_latency_ms`, `max_memory_gb`…), chỉ được import bởi `tests/stt/test_config.py`.
- **Nguyên nhân gốc rễ:** cơ chế quản lý bộ nhớ/idle-unload thật sự nằm ở `ModelGateway` (`api/services/model_gateway.py:393-443`, `_auto_unload_loop`) với timeout hardcode theo từng model trong `api/services/gateway_setup.py` (dòng 92, 118, 151, 184, 216, 251) — không đọc bất kỳ field nào từ `OptimizationConfig`. Đã xác nhận độc lập bằng grep toàn repo và bằng `refactor_tool(mode=dead_code)` (cả hai đều không tìm thấy caller production).
- **Đề xuất fix:** xoá `optimization_config.py`, hoặc nếu ý định ban đầu là cấu hình hoá `gateway_setup.py`, nối `qwen_timeout_ms`/`max_memory_gb`/`enable_auto_memory_management` thật vào đó.

#### 5. Idle-timeout của model CRITICAL không bao giờ có tác dụng

- **Loại:** dead-pipeline / complexity nhỏ (thấp nhưng gây hiểu nhầm)
- **Vị trí:** `ai-service/api/services/gateway_setup.py:91-92` (Qwen đăng ký `priority=ModelPriority.CRITICAL`, `idle_timeout_seconds=600`), `ai-service/api/services/model_gateway.py:426-427` (`_auto_unload_loop` bỏ qua mọi model có `priority == CRITICAL`).
- **Nguyên nhân gốc rễ:** giá trị `idle_timeout_seconds=600` gán cho Qwen không bao giờ được đọc tới vì priority CRITICAL luôn `continue` trước khi kiểm tra idle time. Không gây lỗi runtime, nhưng là code gây hiểu lầm khi tuning.
- **Đề xuất fix:** bỏ tham số `idle_timeout_seconds` khỏi model CRITICAL, hoặc thêm comment giải thích nó bị bỏ qua có chủ đích.

#### 6. Content ETL (checksum-verified) chỉ chạy thủ công qua CLI — không có lịch tự động hay cảnh báo dữ liệu cũ

- **Loại:** business-logic / optimization (SCALE/OPS)
- **Vị trí:** `ai-service/api/services/content_etl/pipeline.py` (`ETLPipeline.run()` — có verify-and-fail SHA256 thật ở `downloader.py:75-155`, raise `DownloadSecurityError` khi checksum sai), entrypoint duy nhất là `ai-service/api/services/content_etl/cli.py`. `api/routes/content_agent.py` chỉ đọc snapshot đã có sẵn trên `CONTENT_ETL_STORAGE_ROOT` (dòng 206-255), không có route/cron nào gọi `ETLPipeline.run()`.
- **Nguyên nhân gốc rễ:** tách biệt "ingest thô có xác minh checksum" (CLI, thủ công) khỏi "sinh nội dung từ snapshot đã duyệt" (route, tự động) là thiết kế hợp lý về an toàn, nhưng không có cơ chế nào theo dõi độ mới của snapshot hay tự động refresh — nếu operator quên chạy CLI, dữ liệu CEFR/CMU/OEWN/Tatoeba có thể cũ vô thời hạn mà không ai biết.
- **Đề xuất fix:** thêm job định kỳ (cron/Celery beat) gọi `content_etl sync`, hoặc tối thiểu một metric/alert dựa trên tuổi của snapshot đang active.

### Low

#### 7. `retrieve_node` chạy Stage 1 (KG) và Stage 2 (vector/RetrievalServiceV3) tuần tự dù có ngân sách độc lập

- **Loại:** optimization
- **Vị trí:** `ai-service/api/services/trace_cag/retrieve.py:81-573` (`retrieve_node`) — Stage 1 (dòng ~160-198, KG query) `await` xong rồi mới tới Stage 2 (dòng ~243-300, `retrieval_v3.retrieve(...)`), mỗi stage có ngân sách ms riêng (`TRACECAG_RETRIEVE_BUDGET_KG_MS=120`, `TRACECAG_RETRIEVE_BUDGET_VECTOR_MS=80`) nhưng được trừ vào cùng một đồng hồ tuần tự (`_elapsed_ms()`).
- **Nguyên nhân gốc rễ:** hai nguồn evidence độc lập (KG lexical index vs. RetrievalServiceV3 centrality/community) không phụ thuộc dữ liệu lẫn nhau ở input (cả hai chỉ cần `user_input` + `kg_concepts` đã có sẵn từ đầu hàm) nhưng code gọi `await` lần lượt thay vì `asyncio.gather`. Đây là node chạy trên **mọi lượt chat thật** (không chỉ benchmark), nên đây là chi phí latency thật, không phải nợ benchmark-only.
- **Đề xuất fix:** chạy Stage 1 và Stage 2 song song bằng `asyncio.gather`, giữ nguyên logic budget-early-exit cho từng nhánh riêng; có thể giảm phần lớn latency retrieval vốn đã tối ưu (KG ~40ms sau fix trước đó) khi chồng lấp với vector search (~80ms budget).

#### 8. Các file/hàm quá lớn còn sót lại sau lần tách nodes_v2/generate/retrieve

- **Loại:** complexity (không phải lỗi, backlog dọn dẹp)
- **Vị trí:** `ai-service/api/services/trace_cag/cache_utils.py` (1427 dòng, hàm `cache_gate_node` một mình 420 dòng, dòng 1007-1426), `ai-service/api/services/trace_cag/nodes_v2.py` (1028 dòng), `ai-service/api/services/trace_cag/retrieve.py::retrieve_node` (493 dòng riêng một hàm, dòng 81-573), `ai-service/api/services/kg_service_v3.py::KnowledgeGraphServiceV3` (834 dòng), `ai-service/api/services/lexi_chat_service.py` (947 dòng).
- **Đề xuất fix:** không cấp bách, nhưng `retrieve_node` giờ là monolith lớn nhất còn lại hậu tách file — nên là ứng viên tiếp theo nếu team tiếp tục refactor theo hướng đã làm với `nodes_v2.py`/`generate.py`.

## Đối chiếu với các mục đã yêu cầu kiểm tra cụ thể

- **Ingestion → KG → TRACE-CAG → generate → API response, kể cả `integration_trace_cag.py`:** nối dây đầy đủ và thật — `service/tracecag_service/adapters/lexilingo.py` gọi đúng `graph.py::TraceCAGPipeline.analyze()` với `to_pipeline_kwargs()` khớp chính xác chữ ký thật của `analyze()` (đã đối chiếu từng field). Không có dead-end. Vấn đề duy nhất trong luồng này là #1 và #2 ở trên.
- **Voice loop (STT ensemble/fallback, session lifecycle, idle-unload):** `STTModelRegistry.start()` (`api/services/stt/model_registry.py:40-81`) có cascade fallback thật (Moonshine → Sherpa → Faster-Whisper-as-primary) khi model chính load lỗi lúc khởi động — không phải dead code. `SessionManager` (`api/services/stt/session_manager.py`) có đầy đủ idle timeout, hard limit, resume window, cleanup loop; `api/routes/stt.py:344-402` gọi `mark_disconnected`/`release_connection` đúng trong `except WebSocketDisconnect`/`finally`. Auto-unload model (`ModelGateway._auto_unload_loop`) thực sự được khởi động qua `gateway.start()` trong `gateway_setup.setup_gateway()`, được gọi từ `lifespan()` trong `main.py:227-238` khi `USE_GATEWAY=true` (mặc định true). Không phải "configured but unused" — chỉ có bug nhỏ #5 ở trên.
- **`lexi_chat` orchestration extraction (`lexi_pipeline_helpers.py`):** không có logic mồ côi hay trùng lặp — `lexi_chat_service.py` import và dùng đúng cả 3 helper (`sanitize_lexi_response`, `synthesize_tts`, `transcribe_audio`), không định nghĩa lại song song. Có 1 bug thật liên quan (#3) nhưng không phải do extraction làm rơi rớt error handling — try/except quanh generation vẫn đầy đủ.
- **`content_etl` production wiring + checksum verify-and-fail:** đã trả lời ở #6 — checksum path là thật và fail-closed, nhưng pipeline chỉ chạy thủ công.
- **Learner-state integration (outbox, circuit breaker):** **KHÔNG** giống backend — đây là một trường hợp *đã nối dây thật*, không phải "configured but unused". `learner_observation_spool.py` (outbox + lease-based `SpoolForwarder` + reconciliation queue) được gọi thật từ cả `api/routes/chat.py:341-344` và `api/services/lexi_chat_service.py:568-571,918-920`; `start_learner_observation_forwarder()` được khởi động trong `lifespan()` khi `LEARNER_STATE_MODE != "off"`. Không có vấn đề cần báo cáo ở đây ngoài các `except Exception: pass` vô hại quanh việc ghi metric telemetry (không ảnh hưởng đường ghi dữ liệu chính).
- **CEFR gating / Vietnamese hints / STT confidence gating (business logic sanity):** `kg_service_v3.py::query_concepts()` áp dụng boost theo khoảng cách CEFR thật (`CEFR_ORD`, dòng 902-914) chứ không chỉ dùng level làm cache key suông. `vietnamese_node` có cascade Qwen → Gemini → chuỗi hardcode 4 ngôn ngữ, xuống cấp hợp lý (`nodes_v2.py:735-836`) — không có setting `ENABLE_VIETNAMESE_HINTS` nào tồn tại trong code (routing dựa trên level+error trong `edges.py`, không phải feature flag toàn cục — không phải bug, chỉ khác tên so với giả định ban đầu). `STT_CONFIDENCE_ACCEPT`/`STT_CONFIDENCE_VERIFY` gate thật sự quyết định có gọi verifier hay không (`verifier_router.py:19-34`), không phải tính rồi bỏ.

## Debt Heat Map

| Khu vực | Bug | Dead-pipeline | Business-logic | Optimization |
|---|---|---|---|---|
| `service/tracecag_service` + `integration_trace_cag.py` | 2 (#1, #2) | 0 | 0 | 0 |
| `lexi_chat_service.py` / `trace_cag/generate.py` | 1 (#3) | 0 | 0 | 0 |
| `model_gateway.py` / `gateway_setup.py` / `optimization_config.py` | 0 | 2 (#4, #5) | 0 | 0 |
| `content_etl` | 0 | 0 | 1 (#6) | 0 |
| `trace_cag/retrieve.py` + large files (`cache_utils.py`, `nodes_v2.py`, `kg_service_v3.py`) | 0 | 0 | 0 | 2 (#7, #8) |

## Top 5 First Strikes (ưu tiên xử lý trước)

1. **#1** — Namespace Redis conversation-cache key theo tenant trước khi bật external integration ở production (rủi ro rò rỉ dữ liệu người dùng cao nhất, fix nhỏ ~10 dòng).
2. **#2** — Chuyển `ExternalRequestCache` sang Redis TTL (chặn memory leak + đảm bảo idempotency đúng nghĩa khi scale ngang).
3. **#3** — Sửa `stream_llm_tokens` trả về provider thật, dừng ghi sai `model_used` vào cache/telemetry.
4. **#7** — Song song hoá Stage 1/Stage 2 trong `retrieve_node` bằng `asyncio.gather` — tác động tới latency mọi lượt chat thật, effort thấp.
5. **#4** — Xoá `OptimizationConfig` chết để tránh kỹ sư tương lai tưởng nhầm đó là nơi tuning thật.
