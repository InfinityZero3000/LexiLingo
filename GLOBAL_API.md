# LexiLingo Global API Documentation

Tài liệu này tổng hợp các điểm cuối (endpoints) quan trọng và cách các thành phần (Backend, AI, Flutter) giao tiếp với nhau.

## Tổng quan hệ thống
- **Backend Service (FastAPI)**: Quản lý logic nghiệp vụ, người dùng, tiến độ, và dữ liệu cốt lõi. (Cổng mặc định: `8000`)
- **AI Service (FastAPI)**: Xử lý các tác vụ AI như Speech-to-Text, Text-to-Speech, và Generative AI (CAG). (Cổng mặc định: `8001`)
- **Flutter App**: Client chính tiêu thụ các API từ cả hai dịch vụ trên.

---

## 1. Authentication & User Management
Tất cả các API yêu cầu JWT Token trong Header: `Authorization: Bearer <token>`

| Chức năng | Phương thức | Endpoint | Dịch vụ |
| :--- | :--- | :--- | :--- |
| Đăng ký | POST | `/api/auth/register` | Backend |
| Đăng nhập | POST | `/api/auth/login` | Backend |
| Lấy thông tin cá nhân | GET | `/api/auth/me` | Backend |
| Cập nhật Profile | PUT | `/api/users/me` | Backend |
| Đăng ký Token thiết bị | POST | `/api/devices` | Backend |

---

## 2. Learning & Vocabulary
Hệ thống sử dụng Clean Architecture để quản lý bài học và từ vựng.

| Chức năng | Phương thức | Endpoint | Dịch vụ |
| :--- | :--- | :--- | :--- |
| Lấy danh sách khóa học | GET | `/api/courses` | Backend |
| Lấy Roadmap khóa học | GET | `/api/learning/courses/{id}/roadmap` | Backend |
| Bắt đầu bài học | POST | `/api/learning/lessons/{id}/start` | Backend |
| Nộp câu trả lời | POST | `/api/learning/attempts/{id}/answer` | Backend |
| Hoàn thành bài học | POST | `/api/learning/attempts/{id}/complete` | Backend |
| Lấy từ vựng đến hạn | GET | `/api/vocabulary/due` | Backend |
| Ôn tập từ vựng (SRS) | POST | `/api/vocabulary/review/{id}` | Backend |

---

## 3. Gamification & Progress
Hệ thống hỗ trợ XP, Streak và Achievements để tăng tính tương tác.

| Chức năng | Phương thức | Endpoint | Dịch vụ |
| :--- | :--- | :--- | :--- |
| Lấy thống kê tiến độ | GET | `/api/progress/me` | Backend |
| Lấy Leaderboard | GET | `/api/gamification/leaderboard` | Backend |
| Kiểm tra Achievements | POST | `/api/gamification/achievements/check` | Backend |
| Mua vật phẩm Shop | POST | `/api/gamification/shop/purchase` | Backend |
| Cập nhật Streak | POST | `/api/progress/streak/update` | Backend |

---

## 4. AI & Multimedia Features
Các tính năng thông minh được xử lý bởi `ai-service`.

| Chức năng | Phương thức | Endpoint | Dịch vụ |
| :--- | :--- | :--- | :--- |
| Chuyển giọng nói -> Text | POST | `/api/stt` | AI |
| Chuyển text -> Giọng nói | POST | `/api/tts` | AI |
| Chat với Lexi (AI Tutor) | POST | `/api/lexi_chat/chat` | AI |
| Tạo bài tập từ vựng AI | POST | `/api/cag/vocabulary` | AI |
| Tạo bài tập Grammar AI | POST | `/api/cag/grammar` | AI |
| WebSocket Stream | WS | `/api/conversation/stream` | AI |

---

## 5. Admin & Analytics
Dành cho trang quản trị và thống kê hệ thống.

| Chức năng | Phương thức | Endpoint | Dịch vụ |
| :--- | :--- | :--- | :--- |
| Quản lý khóa học | GET/POST | `/api/admin/courses` | Backend |
| Nhập từ vựng số lượng lớn| POST | `/api/admin/vocabulary/bulk-import` | Backend |
| Dashboard KPI | GET | `/api/analytics/dashboard/kpis` | Backend |
| Theo dõi lỗi AI | POST | `/api/testing/workflow/diagnose` | AI |

---

## Cách Flutter gọi API
Flutter sử dụng `Dio` hoặc `http` kết hợp với `Repository Pattern`.

**Mẫu gọi API trong Flutter:**
```dart
// lib/data/repositories/course_repository.dart
Future<List<Course>> getCourses() async {
  final response = await dio.get('/api/courses');
  final data = ApiResponse<List<dynamic>>.fromJson(response.data);
  return data.data.map((e) => Course.fromMap(e)).toList();
}
```

**Mẫu gọi AI Service:**
```dart
// lib/data/repositories/stt_repository.dart
Future<String> transcribe(List<int> audioBytes) async {
  final formData = FormData.fromMap({
    'file': MultipartFile.fromBytes(audioBytes, filename: 'audio.wav'),
  });
  final response = await aiDio.post('/api/stt', data: formData);
  return response.data['text'];
}
```

---

## Lưu ý quan trọng
1. **ApiResponse Envelope**: Tất cả các phản hồi từ Backend đều được bọc trong một envelope chuẩn:
   ```json
   {
     "success": true,
     "data": { ... },
     "message": "...",
     "meta": { ... }
   }
   ```
2. **CORS**: Đảm bảo các origin của Flutter (Mobile/Web) được cấu hình trong `ALLOWED_ORIGINS` của cả hai dịch vụ.
3. **Pydantic V2**: Cả hai dịch vụ Python đều sử dụng Pydantic V2 để validation dữ liệu.
