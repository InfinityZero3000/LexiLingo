# TRACE-CAG — báo cáo so sánh chỉ số

**Ngày:** 2026-08-30 · **Tập:** HotpotQA distractor, n=64, seed=42 · **Mô hình đọc:**
`qwen/qwen3.6-27b` (Groq) chung cho cả ba hệ · **Chuẩn hoá:** SQuAD canonical
(`tracecag_bench/metrics/text.py`) · **Validation:** PASS, 0 lỗi, 0 fallback nhà cung cấp.

Nguồn số: `model-development/reports/benchmarks/hotpotqa_n64_cleanup.json` (TRACE-CAG và
CAG thuần, cùng một lần chạy) và
`model-development/baselines/hipporag_real/runs/hotpotqa_strictrecall.json` (HippoRAG 2).

> Báo cáo này **chỉ so sánh chỉ số**. Phần diễn giải kiến trúc và lịch sử tối ưu nằm ở
> `tracecag_benchmark_report_2026-08-26.md`; phần trạng thái từng cơ chế nằm ở
> `tracecag_end_to_end_audit_2026-07-17.md`.

---

## 1. Bảng tổng

| Hệ | EM | F1 | R@5 | allSupport@5 | Đệm | Độ trễ lạnh |
|---|---|---|---|---|---|---|
| CAG thuần | 62,5% | 74,5% | 74,2% | 50,0% | 47,7% | 2 112 ms |
| **TRACE-CAG** | **62,5%** | **74,7%** | **78,9%** | **59,4%** | **48,4%** | 2 225 ms |
| HippoRAG 2 (gói chính thức) | 53,1% | 69,7% | **85,9%** | — | không có | 65 700 ms |

Ba câu đọc được từ bảng này, và không câu nào là "TRACE-CAG thắng":

1. TRACE-CAG **truy hồi tốt hơn CAG thuần** ở mọi chỉ số, nhưng **EM bằng nhau**.
2. HippoRAG **truy hồi tốt hơn cả hai** (R@5 85,9%) và **trả lời tệ hơn cả hai**.
3. Cách biệt EM giữa TRACE-CAG và HippoRAG phần lớn là **kỷ luật định dạng đáp án**,
   không phải chất lượng suy luận — xem mục 4.

> **Về con số HippoRAG.** Bảng trên trích **một lần chạy** (`strictrecall`, 29/08) vì mọi
> đối sánh từng câu ở mục 4 đều dựa trên lần chạy đó. Lần chạy `v3` cùng cấu hình cho
> EM 56,2% / F1 73,0% — 4/64 câu khác nhau do nhiễu mô hình. Khi trích **chỉ mình bảng
> tổng** mà không kèm phân tích từng câu, hãy ghi dạng khoảng **53,1--56,2% / 69,7--73,0%**
> như các tài liệu khác.

---

## 2. TRACE-CAG so với CAG thuần — cùng một lần chạy, cùng mô hình

Đây là phép so sánh sạch nhất trong toàn bộ tài liệu: hai chế độ chạy trong **cùng một
tiến trình benchmark**, cùng seed, cùng nhà cung cấp, khác nhau đúng một thứ là nhánh đồ thị.

| Chỉ số | CAG thuần | TRACE-CAG | Δ |
|---|---:|---:|---:|
| **EM** | 62,5% | 62,5% | **±0,0** |
| **F1** | 74,5% | 74,7% | +0,3 |
| recall@5 | 74,2% | 78,9% | **+4,7** |
| recall@10 | 94,5% | 96,1% | +1,6 |
| precision@5 | 30,6% | 32,5% | +1,9 |
| hit@5 | 98,4% | 98,4% | ±0,0 |
| **allSupport@5** | 50,0% | 59,4% | **+9,4** |
| allSupport@10 | 89,1% | 92,2% | +3,1 |
| answerInContext@5 | 57,8% | 62,5% | +4,7 |
| MRR@5 | 84,4% | 87,0% | +2,6 |
| nDCG@5 | 71,3% | 74,7% | +3,4 |
| MAP@5 | 63,3% | 66,4% | +3,1 |
| tỉ lệ trúng đệm | 47,7% | 48,4% | +0,8 |
| độ trễ lạnh | 2 112 ms | 2 225 ms | +113 ms |
| prompt tokens | 61 015 | 61 093 | +78 |

**Mọi chỉ số truy hồi đều dương, chỉ số đáp án thì không.** Nhánh đồ thị đưa thêm 9,4 điểm
câu hỏi vào trạng thái "đủ cả hai đoạn hỗ trợ" — chính là điều kiện cần để trả lời một câu
2-hop — mà EM không nhúc nhích.

### 2.1 Hai hệ trả lời giống nhau 92% số câu

Đối sánh từng câu ở lượt lạnh (n=64), so chuỗi đáp án thô:

```
cả hai đúng   38     chỉ CAG thuần đúng   2
cả hai sai    22     chỉ TRACE-CAG đúng   2
đáp án khác chuỗi nhau: 5/64  (92% số câu hai hệ trả lời y hệt)
```

Bốn câu lệch nhau, chia đều hai chiều:

| gold | TRACE-CAG | CAG thuần |
|---|---|---|
| `no` | **no** ✓ | yes |
| `Pedro Rodríguez` | **Pedro Rodríguez** ✓ | unknown |
| `Kansas Song` | in the Kansas City metropolitan area… | **Kansas Song** ✓ |
| `1838` | 1968 | **1838** ✓ |

EM bằng nhau ở đây **không phải hai hệ khác nhau tình cờ trùng điểm**. Chúng sinh ra gần
như cùng một đầu ra. Ngữ cảnh tốt hơn đi vào bộ đọc, cùng một đáp án đi ra.

### 2.2 Vì sao đây là kết quả chứ không phải lỗi đo

Có thể nghi ngờ rằng chênh lệch truy hồi bị nuốt mất ở khâu cắt ngữ cảnh. Không phải:
`answerInContext@5` cũng tăng +4,7 điểm, nghĩa là chuỗi đáp án **thật sự lọt vào cửa sổ mà
mô hình nhìn thấy** thường xuyên hơn. Bộ đọc nhìn thấy nhiều đáp án đúng hơn và vẫn viết ra
cùng một câu trả lời.

---

## 3. Đệm — con số 48,4% nghĩa là gì và không nghĩa là gì

Đây là chỗ dễ đọc sai nhất trong toàn bộ báo cáo, nên tách riêng.

Giao thức benchmark đặt `cache_repeats: 2`: mỗi câu hỏi chạy **hai lượt**, một lạnh một ấm
(64 câu → 128 quan sát mỗi chế độ). Phân rã theo lượt:

| | lượt lạnh | lượt ấm | tổng |
|---|---:|---:|---:|
| CAG thuần trúng đệm | 0/64 | 61/64 | 47,7% |
| TRACE-CAG trúng đệm | 0/64 | 62/64 | 48,4% |

Nên **48,4% không phải tỉ lệ tái dùng ngữ nghĩa**. Nó là trần 50% do giao thức áp đặt, và
TRACE-CAG chạm 96,9% của cái trần đó ở lượt ấm. Đo được là "hỏi lại đúng câu vừa hỏi thì
trả lại được", không hơn.

### 3.1 L1 chưa từng kích hoạt một lần nào

Phân rã theo tầng đệm, cả 128 quan sát mỗi chế độ:

| tầng | CAG thuần | TRACE-CAG |
|---|---:|---:|
| L0 (trùng khớp chính xác) | 61 | 62 |
| **L1 (theo bucket đồ thị)** | **0** | **0** |
| không trúng | 67 | 66 |

`l1_rate = 0.0` ở **mọi chế độ, mọi lần chạy**. Các báo cáo benchmark tháng 5–6/2026 cũng
ghi đúng con số này; chúng đã bị xoá ngày 2026-08-30 vì mọi số liệu khác đã hết hiệu lực
(chạy trên `llama-3.1-8b-instant` đã ngừng cung cấp, đường cơ sở `hipporag_proxy` tự cài
lại, n=20, cho phép fallback). Cần đọc lại thì lấy từ lịch sử git:
`git log --diff-filter=D --oneline -- 'ai-service/docs/tracecag_benchmark_report_2026-0[56]*'`.
Ba tháng, không một lần trúng.

Đây là điểm cần nói thẳng: **L1 chính là cơ chế phân biệt TRACE-CAG với một CAG có đệm
thường**. L0 là đệm trùng khớp chính xác — bất kỳ hệ nào cũng làm được, HippoRAG không có
chỉ vì nó không cài đệm. Phần thật sự mới — tái dùng chéo câu hỏi qua bucket đồ thị, có
chứng chỉ chấp nhận và vá theo slot — **chưa được benchmark nào chạm tới**.

### 3.2 Nguyên nhân: đường **ghi** L1 bị đóng trong benchmark

Lời giải thích lưu truyền từ 2026-05-31 là *"benchmark dùng mẫu độc nhất, không có trùng lặp
ngữ nghĩa nên L1 không kích hoạt; L1 sẽ hiệu quả trong production"*. **Sai.**

Bằng chứng phản bác có sẵn trong repo: bộ dữ liệu `query_clusters` được tạo đúng để kiểm L1
(các cụm câu hỏi paraphrase của cùng một câu). Nó **đã chạy** ngày 2026-07-10
(`public-qa-query_clusters-qwen_qwen3-32b.json`, validation PASS) và cho
**`l1_rate = 0.0`** — y hệt. Có câu gần nghĩa cũng không trúng.

Truy vết trong dữ liệu chạy: **64/64 quan sát lạnh** kết thúc với
`cache_gate_meta.reasons = ('no_compatible_candidate',)` và `risk = 1.0`. Trong
`cache_gate_node`, giá trị đó là nhánh mặc định `best_rejection or (1.0,
("no_compatible_candidate",))` — nghĩa là `best_rejection` vẫn là `None`, tức **vòng lặp
duyệt ứng viên chưa chạy dù chỉ một lần**. Không có ứng viên nào để mà từ chối. Vấn đề nằm
trước cổng PCC, không phải tại cổng PCC.

Ngược lên khâu ghi: `_register_l1_bucket_aliases` chỉ được gọi khi `_is_pcc_stable(state)`
đúng. Hàm đó (`cache_utils.py:455`) chấp nhận theo một trong hai lối:

| lối | điều kiện | benchmark cấp gì |
|---|---|---|
| oracle | `benchmark_metadata._tracecag_state["concepts"]` khác rỗng | `_public_qa_state()` chỉ trả `evidence_hash`, `source_version`, `freshness_class` — **không có `concepts`** |
| chẩn đoán | `diagnosis_confidence ≥ 0,70` **và** `diagnosis_root_causes` khác rỗng | nhánh bypass (`nodes_v2.py:417`) đặt `confidence = 1.0` nhưng `root_causes = []` |

Cả hai lối đều đóng. Kiểm bằng thực thi trực tiếp trên trạng thái đúng như benchmark tạo ra:

```
khoá _tracecag_state benchmark cấp: ['evidence_hash', 'freshness_class', 'source_version']
có 'concepts'?  False
_is_pcc_stable(benchmark)        = False
_is_pcc_stable(có root_cause)    = True     ← đối chứng
_is_pcc_stable(có concepts)      = True     ← đối chứng
```

**Kết luận: L1 không thể trúng trong benchmark theo đúng cấu tạo.** Không có bucket nào từng
được ghi, nên không có ứng viên nào để đọc. Đây là lý do `query_clusters` cũng cho 0% — và
là lý do mọi kế hoạch kiểu "chạy thêm một tập dữ liệu khác để đo L1" đều sẽ cho 0%.

Chú ý sắc thái: docstring của `_is_pcc_stable` **mô tả đúng** ý định — *"Benchmark bypass
skips the diagnosis stage; oracle-provided concepts anchor the bucket instead"*. Lối thoát
oracle đã được thiết kế, chỉ là **harness không bao giờ cấp khoá `concepts`**. Đây là lệch
pha giữa hai module, không phải thiếu sót thiết kế.

**Việc cần làm (chưa làm, ngoài phạm vi lần này):** cho `_public_qa_state()` phát kèm
`concepts` — dùng chính `kg_seed_concepts` mà `kg_expand_node` đã sinh ra — rồi chạy lại
`query_clusters`. Chỉ khi đó con số L1 mới có nghĩa. Chừng nào chưa làm, **không được ghi L1
vào bất kỳ tuyên bố định lượng nào**, và cũng không được nói "L1 sẽ hiệu quả trong
production" — chưa có phép đo nào cho phép nói câu đó.

---

## 3.3 Sửa và đo: L1 chạy lần đầu tiên (2026-08-30)

Ba thay đổi, mỗi thay đổi đo riêng trên `query_clusters` (32 mẫu, `cache-repeats 1`
để paraphrase buộc phải trúng L1 chứ không phải L0).

| Giai đoạn | EM | F1 | L1 | lỗi |
|---|---:|---:|---:|---:|
| 1. mở cổng ghi L1 | 50,0% | 68,4% | **0,0%** | 0 |
| 2. + khai báo `patchable_slots` | 25,0% | 52,3% | **75,0%** | 0 |
| 3. + lọc token nội bộ khỏi bản vá | **50,0%** | 67,9% | **75,0%** | 0 |

**Giai đoạn 1 — cổng ghi.** `_is_pcc_stable` nay chấp nhận `kg_seed_concepts` mà
`kg_expand_node` thực sự sinh ra, thay vì chỉ chấp nhận `diagnosis_root_causes` (vốn chỉ tồn
tại khi người học mắc một trong năm lỗi ngữ pháp được ánh xạ). Lý do từ chối trong dữ liệu
chạy đổi hẳn: từ **64/64 `no_compatible_candidate`** (không có gì để so) sang **28/32 ca
đánh giá ứng viên thật**, với risk 0,046–0,152. Nhưng L1 vẫn 0%, vì:

**Giai đoạn 2 — khai báo slot.** Tái dùng thẳng đòi `query_norm` **giống hệt**, nên một câu
diễn đạt lại luôn rơi vào nhánh *patch*; mà `_patch_allowed` từ chối mọi bản vá khi chưa slot
nào được khai báo — và không nơi nào trong repo khai báo. Sau khi harness khai báo
`patchable_slots`, L1 trúng **75%**: đúng bằng thiết kế bộ dữ liệu (8 cụm × 4 biến thể → 8
lượt lạnh, 24 lượt trúng).

Nhưng EM **sụp một nửa**, và đó là một lỗi thật chứ không phải nhiễu:

```
gold = Pedro Rodríguez
trả  = "Pedro Rodríguez\n\n(Also related: token:ab, token:po)"
```

**Giai đoạn 3 — nội dung bản vá.** Nội dung tái dùng **đúng** (`Pedro Rodríguez`, `no`,
`yes`); thứ phá điểm là đuôi `(Also related: …)` mà `_patch_response` nối thêm. Các mục nối
vào là `token:that`, `token:true`, `token:ab` — **mảnh từ vựng nội bộ** do
`_extract_lightweight_graph_concepts` sinh ra để gom câu hỏi gần nghĩa vào cùng bucket. Chúng
là vật liệu so khớp, không bao giờ được thành văn.

Hàng rào an toàn không chặn vì nó **cố ý** không chặn: `_factual_projection` cắt bỏ đúng đuôi
đó trước khi băm, tức coi nó là một slot đã khai báo, miễn trừ khỏi hash sự kiện. Thiết kế
đó đúng cho phản hồi gia sư (thêm một dòng gợi ý là vô hại) và sai cho QA (toàn bộ phản hồi
*chính là* đáp án).

Bản vá lọc chỉ giữ `concept:`/`intent:`. Đây **không phải** vấn đề riêng của benchmark —
người học cũng sẽ đọc thấy "(Also related: token:that, token:true)".

### Cái L1 thực sự đem lại

Ở giai đoạn 3, `tracecag_rapid` phục vụ **75% yêu cầu từ đệm** mà chất lượng không đổi
(EM 50,0% ↔ 50,0%; F1 −0,5 điểm, trong nhiễu):

| | trước | sau | |
|---|---:|---:|---|
| độ trễ trung bình | 1 735 ms | **397 ms** | 4,4× nhanh hơn |
| độ trễ p50 | 479 ms | **5 ms** | |
| prompt tokens | 29 235 | **7 858** | giảm 73% |

`cag_vanilla` đi từ 40,6% lên 46,9% EM với L1 71,9% — nhưng n=32 nên hai câu đã là 6,3 điểm;
**đọc như nhiễu**, không phải như một cải thiện.

### L1 tái hiện trung thành, kể cả cái sai

Đối sánh từng câu giữa lần chạy không-L1 và lần có-L1: **28/32 câu trả lời giống hệt**, và
số câu đúng EM **bằng nhau** (16 = 16). L1 không làm hỏng đáp án; nó phát lại đúng cái mà
đường tính đầy đủ đã sinh ra — **bao gồm cả những đáp án sai**.

Bốn câu lệch là do biến thể 0 (lượt lạnh) của mỗi lần chạy khác nhau vì nhiễu mô hình, rồi
đáp án đó lan sang cả cụm. Đó vừa là tính chất tốt (cả cụm nhất quán) vừa là rủi ro cần biết:
**một đáp án lạnh sai sẽ lan ra toàn cụm** thay vì chỉ sai một lần.

### Hồi quy HotpotQA: không đổi một chỉ số nào

Chạy lại n=64 với cả ba bản vá (validation PASS, 0 lỗi):

| | trước | sau |
|---|---:|---:|
| EM | 62,5% | **62,5%** |
| F1 | 74,7% | **74,7%** |
| R@5 | 78,9% | **78,9%** |
| tỉ lệ đệm | 48,4% | **48,4%** |
| L1 | 0,0% | **0,0%** |

Giống hệt đến từng chỉ số — và **L1 vẫn đúng 0%**. Đây không phải bản vá thất bại mà là
chứng chỉ làm đúng việc: 64 câu hỏi HotpotQA không liên quan nhau, mỗi câu mang ảnh chụp ngữ
cảnh riêng, nên mọi ứng viên chéo câu hỏi bị loại ở `mismatch:evidence_hash` **trước** khi
chấm risk. L1 chỉ kích hoạt ở nơi thật sự có câu hỏi gần nghĩa, và im lặng ở nơi không có.

Đó chính là hành vi cần có, và giờ mới đo được lần đầu.

### Ba cảnh báo bắt buộc kèm theo

1. **`patchable_slots` là tham số giao thức, phải công bố kèm chỉ số đệm** — đúng như ngân
   sách bằng chứng. Nó không mang thông tin đáp án, nhưng nó quyết định con số L1.
2. **Thay đổi harness nằm ở một repo khác.** `ai-service/model-development/` bị repo
   LexiLingo gitignore, nhưng **bản thân nó là một repo git riêng**
   (`InfinityZero3000/Qwen-FineTune-LoRA`). Khai báo `patchable_slots` theo dõi được ở đó —
   nhưng tính đến 2026-08-30 nó **chưa được commit** (lần commit gần nhất: 2026-07-15). Ai
   clone LexiLingo mà không có repo kia sẽ thấy L1 = 0% trở lại và tưởng bản vá vô tác dụng.
   Khi công bố, phải nêu cả hai repo cùng mốc commit.
3. **Production: có thêm năng lực, chưa đổi hành vi.** Đây là tính chất an toàn đáng chú ý
   nhất và nó là cố ý. Bản vá cổng ghi và bản lọc token nằm trong `api/` nên có hiệu lực ở
   prod; việc khai báo `patchable_slots` thì **không** (chỉ harness benchmark khai báo, và
   không route production nào đặt `benchmark_metadata` — đã kiểm bằng grep).

   Hệ quả dây chuyền ở production: bucket **bắt đầu được ghi**, ứng viên **bắt đầu được đánh
   giá**, nhưng `_patch_allowed` vẫn từ chối mọi bản vá vì không slot nào được khai báo, nên
   yêu cầu rơi về tính đầy đủ như trước. Nhánh `reuse` thẳng thì đòi `query_norm` giống hệt —
   mà trường hợp đó L0 đã bắt từ trước. Tức **người dùng thật không nhận thêm một phản hồi
   đệm nào**; chỉ có phần máy móc bắt đầu chạy, với chi phí bị chặn trên
   (`_MEM_BUCKET_MAX_ITEMS = 8`, TTL 2 giờ).

   Đó là cách dàn dựng đúng: prod có năng lực trước, hành vi sau — chờ trả lời được câu hỏi
   thật sự khó là *một câu hỏi diễn đạt khác có được phép nhận lại câu trả lời đã đệm không*.
   Trong benchmark an toàn nhờ `evidence_hash` chặn ứng viên chéo câu hỏi; chat production
   không có mốc cố định tương đương, nên câu trả lời phải đến từ thiết kế, không từ suy diễn.

## 4. TRACE-CAG so với HippoRAG 2 — cách biệt EM phần lớn là định dạng

Đối sánh từng câu, nối theo **chuỗi gold duy nhất** (52/64 câu; 12 câu bị loại vì gold trùng
lặp: `yes`, `no`, `2000`). Nối theo thứ tự là **sai** — đã kiểm: chỉ 1/64 câu khớp gold,
đúng như lỗi `idx` tương đối đã ghi nhận trước đây.

```
trên 52 câu nối được:
  cả hai đúng      24      chỉ TRACE-CAG đúng   6
  cả hai sai       20      chỉ HippoRAG đúng    2
  EM: TRACE-CAG 57,7%   HippoRAG 50,0%
```

Nhìn vào 8 câu lệch nhau thì bức tranh đổi hẳn:

**6 câu HippoRAG thua — 5 câu là lỗi định dạng, không phải lỗi kiến thức:**

| gold | HippoRAG trả lời | loại lỗi |
|---|---|---|
| `1969 until 1974` | `1969-1974` | định dạng |
| `world's best goalkeeper` | `IFFHS World's Best Goalkeeper` | span thừa |
| `2009 Big 12 Conference` | `2009, Big 12` | span thiếu |
| `English Electric Canberra` | `The text identifies the English Electric Canberra as a "British first-…` | bãi suy luận |
| `Fujioka, Gunma` | `Japan` | **sai thật** |
| `Max Martin, Savan Kotecha and Ilya Sal…` | `Information not provided` | **sai thật** |

**2 câu TRACE-CAG thua — 1 trong đó cũng là lỗi định dạng:**

| gold | TRACE-CAG trả lời | loại lỗi |
|---|---|---|
| `Mumbai` | `Mumbai, Maharashtra` | span thừa |
| `Terry Richardson` | `Annie Morton` | **sai thật** |

Tức trong 8 câu quyết định cách biệt, **6 câu là tranh chấp về ranh giới span**, chỉ 3 câu
là sai kiến thức thật (2 của HippoRAG, 1 của TRACE-CAG).

### 4.1 Xác nhận trên toàn tập

| | số câu sai EM | trong đó F1 ≥ 0,5 (gần đúng) | F1 = 0 (sai hẳn) |
|---|---:|---:|---:|
| HippoRAG | 30 | **14 (47%)** | 11 |
| TRACE-CAG | 24 | 10 (42%) | 12 |

Và độ dài đáp án giải thích phần còn lại:

| | trung vị | trung bình | dài nhất | số câu > 20 từ |
|---|---:|---:|---:|---:|
| HippoRAG | 2 từ | **53,5 từ** | **754 từ** | 5/64 |
| TRACE-CAG | 2 từ | 2,3 từ | 12 từ | **0/64** |

Trung vị bằng nhau nhưng trung bình lệch 23 lần: HippoRAG **lưỡng cực** — hoặc trả 1–3 từ,
hoặc xả ra một đoạn suy luận dài. EM chấm 0 cho mọi câu thuộc nhóm sau bất kể nội dung đúng.
TRACE-CAG không bao giờ vượt 12 từ vì có hậu xử lý trích span.

**Hệ quả cho cách phát biểu kết quả.** Câu "TRACE-CAG hơn HippoRAG 9,4 điểm EM" đúng về số
nhưng gây hiểu nhầm về nguyên nhân. Phát biểu đúng hơn: *TRACE-CAG có kỷ luật định dạng đáp
án tốt hơn ở cùng chất lượng suy luận, cộng với chi phí thấp hơn 30 lần.* Khoảng cách F1
(74,7% so với 69,7% = 5,0 điểm) nhỏ hơn khoảng cách EM (9,4 điểm) đúng vì lý do này — F1
tha thứ cho lỗi định dạng còn EM thì không.

Điều này **không** làm mất giá trị của TRACE-CAG. Trả về span sạch là yêu cầu thật của sản
phẩm. Nhưng nó có nghĩa là đóng góp đo được nằm ở khâu hậu xử lý đầu ra, không phải ở
kiến trúc đồ thị.

---

## 5. Lịch sử các lần chạy — TRACE-CAG

| Lần chạy | EM | F1 | R@5 | R@10 | allSup@5 | allSup@10 | lỗi | ghi chú |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| metrics (26/08) | 54,7% | 66,5% | 78,1% | 80,5% | 57,8% | 62,5% | 0 | mốc trước tối ưu |
| optimized (26/08) | 56,2% | 68,6% | 78,9% | 82,0% | 59,4% | 65,6% | 0 | sửa anchor + phủ + cổng IRCoT |
| **bigbudget (26/08)** | **62,5%** | **74,7%** | 78,9% | 96,1% | 59,4% | 92,2% | 0 | **nâng ngân sách bằng chứng 5→9** |
| ~~codex (28/08)~~ | ~~46,9%~~ | ~~53,9%~~ | ~~57,8%~~ | ~~71,1%~~ | ~~42,2%~~ | ~~67,2%~~ | **22** | **KHÔNG HỢP LỆ** — xem dưới |
| nolink (28/08) | 62,5% | 74,7% | 78,9% | 96,1% | 59,4% | 92,2% | 0 | gỡ bridge-snippet |
| cleanup (29/08) | 62,5% | 74,7% | 78,9% | 96,1% | 59,4% | 92,2% | 0 | dọn mã, khoá đệm theo chế độ |

Hai điều cần đọc đúng ở bảng này:

**Lần chạy `codex` không phải một lần suy giảm.** 22 lỗi cứng do HippoRAG v3 lập chỉ mục
song song trên cùng 7 khoá Groq (8000 TPM mỗi khoá). Dòng lỗi có `retrieval_trace` rỗng, kéo
sập chỉ số truy hồi, trông y hệt một hồi quy xếp hạng. **Không bao giờ chạy hai benchmark
đồng thời trên cùng bể khoá**, và luôn kiểm `errors == 0` trước khi đọc bất kỳ con số nào.

**Ba lần chạy cuối cho F1 giống nhau đến từng chữ số** (74,7284%). Các thay đổi ở `nolink` và
`cleanup` không hề chạm vào đầu ra của TRACE-CAG — đúng như thiết kế, vì cả hai đều là gỡ mã
chết và sửa khoá đệm. Đây là bằng chứng tốt rằng chúng thật sự trung tính.

**Đòn bẩy duy nhất có tác dụng thật là ngân sách bằng chứng** (+6,3 EM). Ba bản sửa thuật
toán trước đó chỉ cho +1,5 EM, nằm trong nhiễu một câu.

---

## 6. Nhất quán số liệu giữa các tài liệu

Các tài liệu trước trích `CAG thuần F1 = 74,3%` — con số đó lấy từ lần chạy `nolink`
(28/08), không phải lần chạy cuối. Lần `cleanup` (29/08) cho **74,5%**. Chênh lệch không đổi
kết luận nào (cả hai đều nằm trong nhiễu so với 74,7%), nhưng từ nay **chỉ trích lần chạy
`cleanup`** cho cả hai chế độ để không trộn hai lần chạy trong cùng một bảng.

Tương tự, `allSupport@5 = 57,8%` xuất hiện trong phần chẩn đoán là giá trị **trước** khi nâng
ngân sách; giá trị hiện hành là **59,4%**. Khi trích, luôn kèm mốc thời gian.

---

## 7. Cảnh báo khi đọc

- **n=64, một lát cắt duy nhất.** Biến thiên giữa các lần chạy đo được ~1 câu với
  TRACE-CAG, ~5–6 điểm với CAG thuần và HippoRAG. Chênh lệch một câu (1,6 điểm) **không phải
  một thứ hạng**.
- **Đừng đọc trung bình tích luỹ giữa chừng như một xu hướng.** Trong lần chạy HippoRAG
  29/08, EM chạy giảm từ 75% xuống 50% trông như xuống cấp; đối chiếu từng câu với lần trước
  cho thấy 36/37 câu đầu chấm y hệt, EM theo khối dao động (62,5 / 50,0 / 62,5 / 25,0) chứ
  không giảm. Trung bình chỉ đang hội tụ từ một khởi đầu may mắn về ~53%.
- **`answer_in_context` có hai giá trị khác nhau, đừng lẫn.** `answerInContext@5` = 62,5% (5
  đoạn đầu); tính trên toàn cửa sổ 9–10 đoạn mà bộ đọc thật sự nhận thì là **82,8%**. Trần
  cứng của bộ đọc là con số thứ hai. ~17% số câu nằm ngoài tầm với ở mọi cấu hình bộ đọc.
- **Nối dữ liệu giữa hai hệ phải nối theo nội dung**, không theo chỉ số dòng. Kiểm chứng:
  nối theo thứ tự chỉ khớp gold 1/64 câu.
