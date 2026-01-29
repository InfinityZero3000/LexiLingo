import re

files_to_fix = [
    "app/models/course.py",
    "app/models/progress.py",
    "app/models/vocabulary.py",
    "app/models/gamification.py"
]

for filepath in files_to_fix:
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        original = content
        
        # Remove the UUID import from sqlalchemy.dialects.postgresql
        content = re.sub(
            r'from sqlalchemy\.dialects\.postgresql import UUID.*\n',
            '',
            content
        )
        
        # Handle ARRAY in import - remove from end
        content = re.sub(r', ARRAY\n', '\n', content)
        content = re.sub(r', ARRAY,', ',', content)
        
        # Add the new import after "from app.core.database import Base"
        if 'from app.core.db_types import' not in content:
            content = re.sub(
                r'(from app\.core\.database import Base)',
                r'\1\nfrom app.core.db_types import GUID, GUIDArray',
                content
            )
        
        # Replace UUID(as_uuid=True) with GUID()
        content = re.sub(r'UUID\(as_uuid=True\)', 'GUID()', content)
        
        # Replace ARRAY(GUID()) with GUIDArray()
        content = re.sub(r'ARRAY\(GUID\(\)\)', 'GUIDArray()', content)
        
        if content != original:
            with open(filepath, 'w') as f:
                f.write(content)
            print(f"Fixed: {filepath}")
        else:
            print(f"No changes: {filepath}")
    except Exception as e:
        print(f"Error fixing {filepath}: {e}")

print("Done!")
