# Báo cáo kỹ thuật toàn hệ thống LexiLingo

Nguồn LaTeX của báo cáo kỹ thuật mô tả toàn bộ hệ thống: nghiệp vụ, kiến trúc, thiết kế
(use case/ERD/lớp/tuần tự/triển khai), backend, dữ liệu, AI service, pipeline TRACE-CAG,
thuật toán lõi, pipeline dữ liệu, API, Flutter, admin web, gateway, kiểm thử và vận hành.

## Biên dịch

```bash
cd docs/technical-report
tectonic -X compile main.tex        # -> main.pdf
# hoac:
make        # cung sinh LexiLingo_BaoCaoKyThuat.pdf
```

Yêu cầu: [tectonic](https://tectonic-typesetting.github.io/) (tự tải gói LaTeX khi cần) và
font **Times New Roman** + **Menlo** (có sẵn trên macOS). Trên Linux, đổi `\setmainfont`
trong `main.tex` sang `TeX Gyre Termes` và `\setmonofont` sang `DejaVu Sans Mono`.

Hình vẽ (kiến trúc, use case, ERD, sơ đồ lớp, tuần tự, hoạt động, triển khai, đồ thị
trạng thái TRACE-CAG) được vẽ trực tiếp bằng TikZ trong `tikz-setup.tex` — không phụ
thuộc công cụ ngoài (Graphviz/PlantUML/Mermaid), nên biên dịch được offline hoàn toàn
ngoài lần tải gói LaTeX đầu tiên.

## Cấu trúc

| # | Tệp | Nội dung |
|---|---|---|
| 1 | `chapters/01-tongquan.tex` | Bài toán, phạm vi, thuật ngữ, quy mô mã nguồn |
| 2 | `chapters/02-nghiepvu.tex` | Tác nhân, use case nghiệp vụ, quy trình hoạt động, quy tắc nghiệp vụ |
| 3 | `chapters/03-kientruc.tex` | Nguyên tắc kiến trúc, sơ đồ tổng thể, luồng yêu cầu, ranh giới dịch vụ |
| 4 | `chapters/04-thietke.tex` | Use case hệ thống, ERD, sơ đồ lớp, sơ đồ tuần tự, sơ đồ triển khai |
| 5 | `chapters/05-backend.tex` | FastAPI, middleware, 41 route, dịch vụ nghiệp vụ, Celery |
| 6 | `chapters/06-dulieu.tex` | PostgreSQL (~70 bảng), Redis, MongoDB, KuzuDB |
| 7 | `chapters/07-ai.tex` | Tổ chức AI service, model gateway, giọng nói, tác tử phụ trợ |
| 8 | `chapters/08-tracecag.tex` | Phân tích sâu TRACE-CAG: từng đỉnh, best-first KG, điều khiển thích nghi, IRCoT, đánh giá |
| 9 | `chapters/09-thuattoan.tex` | FSRS delta-rule, chấm điểm CEFR, SCAR-L1, hoà trộn truy xuất, chống cày điểm |
| 10 | `chapters/10-pipeline.tex` | Content ETL, content agent, learner observation, sao lưu |
| 11 | `chapters/11-api.tex` | Tổng hợp API backend + AI service |
| 12 | `chapters/12-flutter.tex` | Clean Architecture, 26 mô-đun, offline, i18n |
| 13 | `chapters/13-admin-gateway.tex` | Admin React, Nginx, Cloudflare WAF, MCP server |
| 14 | `chapters/14-vanhanh.tex` | Kiểm thử, triển khai, quan trắc, hạn chế |
| 15 | `chapters/15-phuluc.tex` | Từ điển thuật ngữ, bảng tra hằng số và tệp then chốt |

Hình raster (`docs/architecture_lexilingo.png`, `docs/tracecag.png`) chỉ dùng ở Chương 3
làm minh hoạ tổng quan gốc; mọi sơ đồ phân tích/thiết kế khác đều là TikZ vector.

## Macro dùng chung (`tikz-setup.tex`)

- `\code{...}` — mã/đường dẫn dài, tự ngắt dòng bằng `seqsplit` (chỉ dùng cho chuỗi
  **không có khoảng trắng**, ví dụ đường dẫn tệp).
- `\codesp{...}` — đoạn có khoảng trắng (lệnh shell, SQL...); không dùng `seqsplit` vì nó
  làm mất ký tự khoảng trắng.
- Kiểu node cho sơ đồ: `svc/dat/cli/gat/inf` (kiến trúc), `proc/dec/term` (hoạt động),
  `ent` (ERD), `uc` + `\stickman` (use case), `lane` (khung nhóm).
- `[section]{placeins}` đã bật — hình không trôi qua khỏi ranh giới `\section` chứa nó.

## Cập nhật nội dung

Số liệu trong chương 1 (số route, số model, số dòng TRACE-CAG…) được đếm từ mã nguồn.
Khi cấu trúc thay đổi đáng kể, đếm lại bằng:

```bash
ls backend-service/app/routes/*.py | wc -l
ls backend-service/app/models/*.py | wc -l
wc -l ai-service/api/services/trace_cag/*.py | tail -1
ls flutter-app/lib/features | wc -l
```

Khi thêm/xoá một chương, nhớ cập nhật đồng thời: `main.tex` (danh sách `\input`), mục
"Cấu trúc báo cáo" ở Chương 1, và mọi tham chiếu `Chương~N` chéo giữa các chương —
`grep -noE "Chương~[0-9]+" chapters/*.tex` để rà soát toàn bộ.
