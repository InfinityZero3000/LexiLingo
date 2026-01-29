# AI Code Review Setup

Dự án này sử dụng **PR-Agent** để tự động review code bằng AI (ChatGPT/Claude) khi tạo Pull Request.

## Tính năng

- ✅ Tự động review code khi tạo/cập nhật PR
- ✅ Đánh giá chất lượng code và đưa ra điểm số
- ✅ Gợi ý cải thiện code (code suggestions)
- ✅ Kiểm tra security vulnerabilities
- ✅ Đánh giá test coverage
- ✅ Tự động tạo PR description
- ✅ Hỗ trợ nhiều lệnh thông qua comments

## Cài đặt

### 1. Thêm OpenAI API Key vào GitHub Secrets

1. Truy cập: `Settings` → `Secrets and variables` → `Actions`
2. Click `New repository secret`
3. Thêm:
   - Name: `OPENAI_API_KEY`
   - Value: API key của bạn (từ https://platform.openai.com/api-keys)

### 2. Cấu hình (Optional)

File `.pr_agent.toml` đã được cấu hình với settings tối ưu cho dự án. Bạn có thể customize:

- Số lượng suggestions
- Loại review (security, tests, performance)
- Model sử dụng (GPT-4, Claude, etc.)

## Sử dụng

### Tự động Review

PR-Agent sẽ **tự động review** khi:
- Tạo PR mới
- Push commits mới vào PR
- Reopen PR

### Manual Commands

Thêm comment vào PR với các lệnh sau:

```bash
/review          # Review toàn bộ PR
/describe        # Tạo/cập nhật PR description
/improve         # Gợi ý cải thiện code
/ask            # Đặt câu hỏi về implementation
/update_changelog # Cập nhật changelog
```

### Ví dụ

1. **Tạo PR mới** → AI tự động review trong vài phút
2. **Comment `/improve`** → Nhận code suggestions
3. **Comment `/ask why did you use this approach?`** → AI trả lời

## Models Supported

### OpenAI (Default)
- GPT-4 Turbo
- GPT-4
- GPT-3.5 Turbo

### Anthropic Claude (Alternative)
Để dùng Claude, thêm vào GitHub Secrets:
- `ANTHROPIC_API_KEY`

Và uncomment trong workflow file:
```yaml
ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
PR_AGENT__MODEL: anthropic/claude-3-5-sonnet-20241022
```

## Ví dụ Review Output

PR-Agent sẽ comment với:

```markdown
## PR Review 🔍

**⏱️ Estimated effort to review: 2 🔵🔵⚪⚪⚪**

**🧪 No relevant tests**  
**🔒 No security concerns identified**

### Code feedback:
- ⚡ Performance: Consider using async/await for API calls
- 🎨 Style: Variable naming could be more descriptive
- 🛡️ Security: Validate user input before processing
- 🧪 Tests: Add unit tests for new service methods
- 📝 Documentation: Add JSDoc comments for public APIs

### 💡 Code Suggestions (5)
...
```

## Best Practices

1. **Review trước khi merge**: Đọc kỹ feedback từ AI
2. **Kết hợp với human review**: AI là công cụ hỗ trợ, không thay thế
3. **Improve code suggestions**: Áp dụng suggestions hợp lý
4. **Ask questions**: Dùng `/ask` để hiểu rõ hơn về codebase

## Troubleshooting

### Lệnh slash commands không hoạt động

**Nguyên nhân có thể:**

1. **Chưa thêm OPENAI_API_KEY**
   - Vào `Settings` → `Secrets and variables` → `Actions`
   - Kiểm tra xem `OPENAI_API_KEY` đã được thêm chưa
   - Nếu chưa, thêm key từ https://platform.openai.com/api-keys

2. **Chưa có PR nào được tạo**
   - Slash commands chỉ hoạt động trong Pull Requests
   - Không hoạt động trong Issues thông thường

3. **Comment sai định dạng**
   - Phải comment `/review` (có dấu `/` ở đầu)
   - Không được có khoảng trắng: `/ review` ❌
   - Phải là comment riêng, không nằm trong code review

4. **Workflow chưa chạy**
   - Vào tab `Actions` trong repo
   - Kiểm tra xem có workflow "AI Code Review" chạy không
   - Xem logs để biết lỗi cụ thể

**Cách test:**

```bash
# Bước 1: Tạo PR mới
1. Tạo PR từ branch feature sang main

# Bước 2: Chờ workflow chạy (1-2 phút)
2. Vào tab "Actions" xem workflow status

# Bước 3: Nếu workflow thành công, thử comment
3. Comment vào PR: /review

# Bước 4: Bot sẽ reply trong vài giây
4. Nếu không, check logs tại Actions tab
```

**Kiểm tra workflow logs:**

1. Vào repo → `Actions` tab
2. Click vào workflow run mới nhất
3. Click vào job "AI Code Review"
4. Xem logs để tìm lỗi:
   - `Error: OPENAI_KEY not found` → Chưa add API key
   - `403 Forbidden` → Permissions issue
   - `Rate limit exceeded` → Vượt quota API

### Workflow không chạy
- Kiểm tra `OPENAI_API_KEY` đã được thêm vào Secrets
- Xem logs tại `Actions` tab
- Đảm bảo workflow file không có lỗi syntax

### API Rate Limit
- Sử dụng GPT-3.5 Turbo cho nhiều PRs
- Thêm fallback models trong config

### Review không chính xác
- Customize `extra_instructions` trong `.pr_agent.toml`
- Thử model khác (GPT-4, Claude)

## Resources

- [PR-Agent Documentation](https://pr-agent-docs.codium.ai/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [OpenAI API](https://platform.openai.com/docs)

## Costs

**OpenAI Pricing** (ước tính):
- GPT-3.5 Turbo: ~$0.01-0.05 per PR
- GPT-4 Turbo: ~$0.10-0.50 per PR

Recommendation: Bắt đầu với GPT-3.5 Turbo, nâng cấp GPT-4 nếu cần review chi tiết hơn.
