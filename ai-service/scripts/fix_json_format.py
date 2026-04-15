import json

def fix_format(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    concepts = data.get("concepts", [])
    edges = data.get("edges", [])
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('{\n')
        f.write(f'  "version": "{data.get("version", "1.0.0")}",\n')
        if "description" in data:
            f.write(f'  "description": "{data["description"]}",\n')
            
        f.write('  "concepts": [\n')
        for i, concept in enumerate(concepts):
            concept_str = json.dumps(concept, ensure_ascii=False, indent=2)
            # Indent each line by 4 spaces
            concept_indented = '\n'.join('    ' + line if j > 0 else '    ' + line for j, line in enumerate(concept_str.split('\n')))
            f.write(concept_indented)
            if i < len(concepts) - 1:
                f.write(',\n')
            else:
                f.write('\n')
        f.write('  ],\n')
        
        f.write('  "edges": [\n')
        for i, edge in enumerate(edges):
            edge_str = json.dumps(edge, ensure_ascii=False)
            f.write(f'    {edge_str}')
            if i < len(edges) - 1:
                f.write(',\n')
            else:
                f.write('\n')
        f.write('  ]\n')
        f.write('}\n')

fix_format('data/knowledge_extended.json')
