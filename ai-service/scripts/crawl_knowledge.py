import json
import os
import asyncio
from crawl4ai import AsyncWebCrawler
import google.generativeai as genai

# Đường dẫn tới file knowledge_extended.json (từ thư mục scripts trỏ ra data)
KG_FILE_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../data/knowledge_extended.json"))

PROMPT_TEMPLATE = """
Bạn là một chuyên gia ngôn ngữ học và kỹ sư dữ liệu xây dựng Knowledge Graph.
Hãy đọc nội dung sau và trích xuất các Concepts (Khái niệm từ vựng/ngữ pháp) và Edges (Mối quan hệ) theo định dạng JSON.

Lưu ý quan trọng:
1. ID của Concept phải theo chuẩn: "concept:vocab.xxx", "concept:grammar.xxx", hoặc "concept:idiom.xxx"
2. Keywords là các từ khóa tiếng Anh viết thường, cách nhau bằng dấu cách.
3. Edges (Mối quan hệ) phải tuân theo format {"from": "id_1", "to": "id_2", "relation": "related_to" (hoặc "prerequisite_of")}.
4. Link các concepts mới với nhau hoặc link với các concepts phổ biến nếu hệ thống yêu cầu.

Trả về CHỈ một object JSON đúng format sau, không kèm bất kỳ markdown code block hay text giải thích nào khác:
{
  "concepts": [
    {"id": "...", "title": "...", "keywords": "..."}
  ],
  "edges": [
    {"from": "...", "to": "...", "relation": "..."}
  ]
}

NỘI DUNG URL CRAWL ĐƯỢC:
"""

async def crawl_and_extract(url: str):
    print(f"1. Đang crawl dữ liệu từ URL: {url} ...")
    async with AsyncWebCrawler() as crawler:
        result = await crawler.arun(url=url)
        markdown_content = result.markdown

    if not markdown_content:
        print("LỖI: Không lấy được nội dung từ URL.")
        return None

    print("2. Đang gửi dữ liệu cho Gemini để trích xuất Knowledge Graph...")
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("LỖI: Bạn chưa set biến môi trường GEMINI_API_KEY. Hãy chạy lệnh: export GEMINI_API_KEY='your_key'")
        return None
        
    genai.configure(api_key=api_key)
    # Sử dụng gemini-2.5-flash để parse (phù hợp với API key của bạn)
    model = genai.GenerativeModel('gemini-2.5-flash')
    
    # Giới hạn độ dài nội dung để tránh vượt quá context window
    prompt = PROMPT_TEMPLATE + markdown_content[:30000]
    
    try:
        response = model.generate_content(prompt)
        raw_json = response.text.strip()
        
        # Tiền xử lý xóa bỏ markdown codeblocks nếu LLM lỡ sinh ra
        if raw_json.startswith("```json"):
            raw_json = raw_json[7:]
        elif raw_json.startswith("```"):
             raw_json = raw_json[3:]
             
        if raw_json.endswith("```"):
            raw_json = raw_json[:-3]
            
        raw_json = raw_json.strip()
        
        parsed_data = json.loads(raw_json)
        return parsed_data
    except Exception as e:
        print(f"Lỗi parse JSON từ Gemini: {e}")
        print("Raw Output từ Gemini:\n", response.text if 'response' in locals() else "No response")
        return None

def merge_into_knowledge_base(new_kg: dict):
    print(f"3. Đang merge data mới vào {KG_FILE_PATH}...")
    
    try:
        with open(KG_FILE_PATH, 'r', encoding='utf-8') as f:
            current_kg = json.load(f)
    except FileNotFoundError:
        print("Không tìm thấy file, tạo cấu trúc mới mặc định.")
        current_kg = {
            "version": "1.0.0", 
            "description": "Extended knowledge base for LexiLingo English Tutor", 
            "concepts": [], 
            "edges": []
        }
        
    # Tạo set các ID hiện có để check trùng lặp
    existing_concept_ids = {c.get("id") for c in current_kg.get("concepts", []) if c.get("id")}
    
    added_concepts = 0
    for concept in new_kg.get("concepts", []):
        c_id = concept.get("id")
        if c_id and c_id not in existing_concept_ids:
            current_kg["concepts"].append(concept)
            existing_concept_ids.add(c_id)
            added_concepts += 1
            
    # Serialize dict ra string để so sánh trùng lặp edge dễ dàng
    current_edges_serialized = {json.dumps(e, sort_keys=True) for e in current_kg.get("edges", [])}
    
    added_edges = 0
    for edge in new_kg.get("edges", []):
        edge_str = json.dumps(edge, sort_keys=True)
        if edge_str not in current_edges_serialized:
            current_kg.setdefault("edges", []).append(edge)
            current_edges_serialized.add(edge_str)
            added_edges += 1
            
    with open(KG_FILE_PATH, 'w', encoding='utf-8') as f:
        f.write("{\n")
        f.write(f'  "version": "{current_kg.get("version", "1.0.0")}",\n')
        if "description" in current_kg:
            f.write(f'  "description": "{current_kg["description"]}",\n')
        f.write("  \"concepts\": [\n")
        for i, concept in enumerate(current_kg.get("concepts", [])):
            concept_str = json.dumps(concept, ensure_ascii=False, indent=2)
            concept_indented = "\n".join("    " + line if j > 0 else "    " + line for j, line in enumerate(concept_str.split("\n")))
            f.write(concept_indented)
            if i < len(current_kg.get("concepts", [])) - 1:
                f.write(",\n")
            else:
                f.write("\n")
        f.write("  ],\n  \"edges\": [\n")
        for i, edge in enumerate(current_kg.get("edges", [])):
            edge_str = json.dumps(edge, ensure_ascii=False)
            f.write(f"    {edge_str}")
            if i < len(current_kg.get("edges", [])) - 1:
                f.write(",\n")
            else:
                f.write("\n")
        f.write("  ]\n}\n")
        
    print(f"✅ HOÀN TẤT! Đã bổ sung thành công {added_concepts} concepts và {added_edges} relationships.")

async def main():
    # Điền URL bất kì bạn muốn crawl lấy từ vựng/ngữ pháp
    # URL ví dụ từ British Council về Travel IELTS
    # Bạn có thể thay đổi bằng URL khác khi chạy
    target_url = "https://learnenglish.britishcouncil.org/vocabulary/b1-b2-vocabulary/travel"
    
    new_data = await crawl_and_extract(target_url)
    if new_data:
        merge_into_knowledge_base(new_data)

if __name__ == "__main__":
    asyncio.run(main())
