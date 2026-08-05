# Backend Audit Report

## Tóm tắt tổng quan

- **Health score:** 58/100 — nền tảng chức năng khá đầy đủ, nhưng còn rủi ro nhất quán dữ liệu, bảo mật outbound/auth và khả năng dựng database sạch.
- **Critical:** 2
- **High:** 5
- **Medium:** 6
- **Low:** 3
- **Tổng số vấn đề:** 16

## Danh sách vấn đề

### Critical

#### 1. Reward/XP không được cập nhật nguyên tử

- **Vị trí:** `app/crud/gamification.py:1`, `app/routes/xp.py:1`, `app/services/starter_reward_service.py:1`
- **Nguyên nhân gốc rễ:** luồng đọc số dư/XP, tính giá trị mới, ghi wallet/XP và ghi nhận sự kiện được thực hiện qua nhiều thao tác độc lập. Hai request đồng thời có thể cùng đọc một trạng thái cũ, ghi đè kết quả hoặc cấp thưởng hai lần.
- **Mức độ:** Critical
- **Đề xuất fix:** gom mỗi nghiệp vụ vào một transaction; khóa hàng người dùng bằng `SELECT ... FOR UPDATE` hoặc dùng câu `UPDATE ... SET value = value + :delta`; thêm idempotency key/unique constraint cho từng sự kiện thưởng và chỉ trả thành công sau khi commit.

#### 2. Race condition ở streak và daily challenge

- **Vị trí:** `app/routes/challenges.py:1`, `app/crud/gamification.py:1`, `app/models/gamification.py:1`
- **Nguyên nhân gốc rễ:** tiến độ challenge và streak được kiểm tra rồi cập nhật theo kiểu read-modify-write, không có khóa hoặc ràng buộc duy nhất đủ mạnh. Retry, nhiều worker hoặc nhiều request hoàn thành bài đồng thời có thể tăng sai tiến độ và phát thưởng lặp.
- **Mức độ:** Critical
- **Đề xuất fix:** cập nhật tiến độ bằng SQL nguyên tử trong transaction; đặt unique constraint cho `(user_id, challenge_id, period)` và sự kiện hoàn thành; khóa bản ghi streak/challenge trước khi đánh giá ngưỡng và cấp thưởng.

### High

#### 3. Chuỗi Alembic không bảo đảm build-from-clean

- **Vị trí:** `alembic/versions/:1`, `alembic/env.py:1`
- **Nguyên nhân gốc rễ:** migration phụ thuộc trạng thái database lịch sử, có nhánh revision/đối tượng được giả định đã tồn tại và có migration vừa thay schema vừa backfill dữ liệu ứng dụng. Database mới không được kiểm chứng thường xuyên bằng `alembic upgrade head` từ rỗng.
- **Mức độ:** High
- **Đề xuất fix:** hợp nhất heads, sửa `down_revision` và thứ tự tạo FK/index; tách schema migration khỏi backfill; thêm CI tạo PostgreSQL rỗng, chạy `upgrade head`, `downgrade` tối thiểu một revision và `upgrade head` lần nữa.

#### 4. SSRF qua các luồng lấy nội dung từ URL

- **Vị trí:** `app/routes/news.py:1`, `app/routes/podcasts.py:1`, `app/routes/youtube.py:1`, `app/tasks/content_prefetch.py:1`
- **Nguyên nhân gốc rễ:** URL/redirect có thể đi tới địa chỉ loopback, private, link-local hoặc metadata service; kiểm tra hostname ban đầu không đủ khi DNS rebinding hoặc redirect xảy ra.
- **Mức độ:** High
- **Đề xuất fix:** chỉ cho phép scheme `https`; resolve và chặn toàn bộ IP private/loopback/link-local/reserved trước mỗi kết nối và redirect; đặt allowlist host cho provider; giới hạn redirect, timeout và kích thước response.

#### 5. OAuth token chưa xác minh audience/issuer đầy đủ

- **Vị trí:** `app/core/dependencies.py:1`, `app/routes/auth.py:1`
- **Nguyên nhân gốc rễ:** token có thể được xác minh chữ ký nhưng thiếu ràng buộc bắt buộc cho `aud`, `iss`, token type và client ID, làm token phát cho ứng dụng/dịch vụ khác có khả năng được chấp nhận.
- **Mức độ:** High
- **Đề xuất fix:** cấu hình allowlist issuer/audience; bắt buộc kiểm tra `iss`, `aud`, `exp`, `nbf`, `iat` và token type; không dùng decode không verify ngoài mục đích quan sát; thêm test token đúng chữ ký nhưng sai audience.

#### 6. Firebase credential file có nguy cơ được đóng gói hoặc commit

- **Vị trí:** `app/core/config.py:1`, `.gitignore:1`, `Dockerfile*:1`
- **Nguyên nhân gốc rễ:** ứng dụng hỗ trợ đường dẫn file service-account trong cây dự án; ignore/build context chưa phải lớp bảo vệ đủ chắc, và secret dài hạn có thể tồn tại trong image layer hoặc lịch sử Git.
- **Mức độ:** High
- **Đề xuất fix:** dùng workload identity/secret mount của runtime; chặn `*firebase*credentials*.json` và service-account JSON trong `.gitignore`, `.dockerignore`, Gitleaks; fail startup nếu production trỏ credential vào source tree; rotate mọi key từng xuất hiện trong Git/image.

#### 7. Internal/partner API key thiếu vòng đời và phạm vi rõ ràng

- **Vị trí:** `app/core/partner_auth.py:1`, `app/routes/integrations.py:1`, `app/core/config.py:1`
- **Nguyên nhân gốc rễ:** hash khóa tĩnh xác thực quyền truy cập nhưng không gắn principal, scope, thời hạn, trạng thái thu hồi hoặc audit identity; việc xoay khóa phụ thuộc cấu hình thủ công.
- **Mức độ:** High
- **Đề xuất fix:** lưu key record có `key_id`, scope, expiry, revoked_at và owner; chỉ lưu hash; hỗ trợ current/previous key trong thời gian chuyển tiếp; log `key_id` thay vì secret và rate-limit theo key.

### Medium

#### 8. Cache invalidation không cùng transaction với dữ liệu nguồn

- **Vị trí:** `app/services/starter_reward_service.py:1`, `app/core/redis_client.py:1`
- **Nguyên nhân gốc rễ:** database commit và xóa/cập nhật Redis là hai thao tác rời, tạo cửa sổ trả dữ liệu wallet/XP cũ hoặc xóa cache trước khi transaction rollback.
- **Mức độ:** Medium
- **Đề xuất fix:** commit DB trước rồi invalidate theo outbox/event hậu commit; cache miss phải đọc từ DB; đặt TTL ngắn cho dữ liệu số dư nhạy cảm.

#### 9. Rate limiting có thể fail-open hoặc không nhất quán giữa worker

- **Vị trí:** `app/core/middleware.py:1`, `app/core/redis_client.py:1`
- **Nguyên nhân gốc rễ:** fallback bộ nhớ cục bộ và xử lý lỗi Redis khiến mỗi process có quota riêng; endpoint nhạy cảm có thể tiếp tục hoạt động khi Redis lỗi.
- **Mức độ:** Medium
- **Đề xuất fix:** dùng Redis atomic script/fixed-window có TTL; fail-closed cho auth, password reset, partner và thao tác cấp thưởng; trả `Retry-After` nhất quán.

#### 10. Background task thiếu idempotency và lease bền vững

- **Vị trí:** `app/tasks/content_prefetch.py:1`, `app/main.py:1`
- **Nguyên nhân gốc rễ:** task có thể chạy ở nhiều replica hoặc được retry mà không có job identity/lease chung, dẫn tới gọi provider và ghi dữ liệu lặp.
- **Mức độ:** Medium
- **Đề xuất fix:** thêm unique job key theo loại tác vụ và cửa sổ thời gian; claim bằng DB/Redis lease có TTL; ghi trạng thái retry/dead-letter và bảo đảm handler idempotent.

#### 11. Error response có nguy cơ lộ chi tiết nội bộ

- **Vị trí:** `app/core/exceptions.py:1`
- **Nguyên nhân gốc rễ:** nhánh xử lý exception có thể đưa type/message kỹ thuật vào response dựa trên thuộc tính runtime, trong khi log và client response chưa tách biệt hoàn toàn.
- **Mức độ:** Medium
- **Đề xuất fix:** production chỉ trả mã lỗi, thông điệp an toàn và request ID; stack trace/type/message chỉ ghi server log; kiểm thử response không chứa DSN, hostname, SQL hoặc secret.

#### 12. Cấu hình security-critical có default hoặc kiểu dữ liệu dễ hiểu sai

- **Vị trí:** `app/core/config.py:1`
- **Nguyên nhân gốc rễ:** nhiều khóa, origin, URL và feature flag được nạp từ chuỗi môi trường; default phát triển có thể lọt vào production, danh sách phân tách bằng dấu phẩy dễ tạo giá trị rỗng hoặc wildcard.
- **Mức độ:** Medium
- **Đề xuất fix:** validator theo môi trường; production fail-fast với secret mặc định, wildcard CORS, HTTP upstream và key rỗng; dùng kiểu `SecretStr`, URL và list đã chuẩn hóa.

#### 13. Thiếu ràng buộc database cho invariant nghiệp vụ

- **Vị trí:** `app/models/gamification.py:1`, `app/models/content.py:1`, `alembic/versions/:1`
- **Nguyên nhân gốc rễ:** một số invariant như số dư không âm, một reward/event duy nhất và trạng thái hợp lệ chủ yếu được giữ ở service layer.
- **Mức độ:** Medium
- **Đề xuất fix:** thêm `CHECK`, `UNIQUE`, FK và enum phù hợp; xử lý `IntegrityError` thành kết quả idempotent hoặc conflict rõ ràng.

### Low

#### 14. Logging chưa thống nhất correlation ID và redaction

- **Vị trí:** `app/core/middleware.py:1`, `app/core/logging_config.py:1`
- **Nguyên nhân gốc rễ:** request ID chưa được truyền xuyên suốt background task/outbound call; header, token hoặc payload có thể bị log bởi nhiều logger khác nhau.
- **Mức độ:** Low
- **Đề xuất fix:** dùng một filter/context cho request ID; redact Authorization, cookie, API key và PII; truyền correlation ID sang task và upstream.

#### 15. Health check chưa phân biệt liveness và readiness đầy đủ

- **Vị trí:** `app/routes/health.py:1`, `app/main.py:1`
- **Nguyên nhân gốc rễ:** một endpoint health có thể vừa kiểm tra process vừa phụ thuộc dịch vụ ngoài, gây restart không cần thiết hoặc báo ready khi dependency bắt buộc chưa hoạt động.
- **Mức độ:** Low
- **Đề xuất fix:** liveness chỉ kiểm tra event loop/process; readiness kiểm tra DB/Redis và dependency bắt buộc với timeout ngắn; không trả chi tiết secret/host nội bộ.

#### 16. Một số module/router tích lũy quá nhiều trách nhiệm

- **Vị trí:** `app/main.py:1`, `app/routes/:1`, `app/crud/gamification.py:1`
- **Nguyên nhân gốc rễ:** wiring, lifecycle, middleware và logic nghiệp vụ phát triển trong các file lớn, khiến transaction boundary và ownership khó nhìn thấy.
- **Mức độ:** Low
- **Đề xuất fix:** chỉ tách khi sửa luồng liên quan: giữ router mỏng, đặt transaction trong service nghiệp vụ và để repository tập trung truy vấn; không tạo interface/factory một implementation.

## Technical debt

1. **Transaction boundary phân tán:** reward, wallet, XP, streak và challenge cần một quy ước chung: service mở transaction, repository không tự commit, cache/event chạy hậu commit.
2. **Migration debt:** cần một baseline CI build-from-clean và quy trình bắt buộc kiểm tra single head trước merge.
3. **Dependency drift:** constraints, requirements và lockfile từng lệch nhau; cần một nguồn version chủ đạo và test đồng bộ tối thiểu.
4. **Auth/config drift:** JWT, OAuth, Firebase, internal key và partner key dùng nhiều cơ chế cấu hình khác nhau; cần chuẩn hóa validation và rotation, không cần dựng auth framework mới.
5. **Test contract drift:** test từng kỳ vọng error schema/phiên bản dependency cũ; các contract công khai cần test tại boundary thay vì bám chi tiết implementation.
6. **Outbound HTTP phân tán:** timeout, redirect, SSRF policy và response-size limit nên đi qua client/helper đang dùng chung; tránh mỗi route tự cấu hình.
7. **Observability debt:** request ID, actor/key ID, idempotency key và transaction outcome chưa tạo được audit trail xuyên suốt.

## Gap

1. Chưa có test cạnh tranh thực tế cho hai request đồng thời cấp reward/XP, cập nhật streak hoặc hoàn tất challenge.
2. Chưa có CI bắt buộc dựng PostgreSQL rỗng và chạy toàn bộ Alembic đến `head`.
3. Chưa có test SSRF cho loopback, IPv6, private IP, DNS rebinding và redirect sang metadata endpoint.
4. Chưa có negative test OAuth/JWT cho đúng chữ ký nhưng sai issuer, audience, token type hoặc client ID.
5. Chưa có secret-scanning gate chuyên biệt cho Firebase service-account JSON và credential file trong Docker context.
6. Chưa có test rotation/revocation/expiry cho partner và internal API keys.
7. Chưa có failure-injection test cho DB commit thành công nhưng Redis/cache/outbox thất bại.
8. Chưa có tải thử đa-worker cho rate limiting, scheduler và background task lease.
9. Chưa có kiểm chứng downgrade/rollback migration và kế hoạch phục hồi khi backfill thất bại.
10. Chưa có security regression test bảo đảm error response/log không lộ secret, DSN, SQL hoặc thông tin provider.
