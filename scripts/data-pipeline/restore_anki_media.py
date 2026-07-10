import os
import json
import glob

def restore_anki_media(base_dir):
    """
    Tìm tất cả các thư mục chứa file 'media' (của Anki) và đổi tên các file media 
    đang được đánh số (0, 1, 2...) về lại tên nguyên bản của chúng.
    """
    # Tìm tất cả file 'media' nằm trong các thư mục con của base_dir
    media_files = glob.glob(os.path.join(base_dir, '*', 'media'))
    
    if not media_files:
        print("Không tìm thấy file 'media' nào để khôi phục.")
        return

    for media_path in media_files:
        dir_name = os.path.dirname(media_path)
        print(f"\nĐang xử lý thư mục: {dir_name}")
        
        try:
            # Đọc mapping từ file JSON 'media'
            with open(media_path, 'r', encoding='utf-8') as f:
                media_mapping = json.load(f)
            
            success_count = 0
            for num_name, real_name in media_mapping.items():
                old_file = os.path.join(dir_name, num_name)
                new_file = os.path.join(dir_name, real_name)
                
                # Nếu file đánh số vẫn tồn tại thì thực hiện đổi tên
                if os.path.exists(old_file):
                    # Tạo thư mục cha nếu real_name có chứa đường dẫn con
                    os.makedirs(os.path.dirname(new_file), exist_ok=True)
                    os.rename(old_file, new_file)
                    success_count += 1
            
            print(f"-> Đã khôi phục tên gốc cho {success_count} file media trong '{os.path.basename(dir_name)}'.")
        
        except Exception as e:
            print(f"Lỗi khi xử lý {media_path}: {e}")

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    restore_anki_media(script_dir)
