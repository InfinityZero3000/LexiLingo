#!/usr/bin/env python3
"""
Validation script to check skill format and consistency
"""

import os
import json
import re
from pathlib import Path
from typing import List, Tuple

class SkillValidator:
    def __init__(self, skills_dir: Path):
        self.skills_dir = skills_dir
        self.errors: List[Tuple[str, str]] = []
        self.warnings: List[Tuple[str, str]] = []
    
    def validate_all(self) -> bool:
        """Validate all skills"""
        skill_dirs = [d for d in self.skills_dir.iterdir() 
                     if d.is_dir() and not d.name.startswith('.')]
        
        print(f"🔍 Validating {len(skill_dirs)} skills...\n")
        
        for skill_dir in skill_dirs:
            self.validate_skill(skill_dir)
        
        # Print results
        if self.errors:
            print("\n❌ Errors found:")
            for skill, error in self.errors:
                print(f"  {skill}: {error}")
        
        if self.warnings:
            print("\n⚠️  Warnings:")
            for skill, warning in self.warnings:
                print(f"  {skill}: {warning}")
        
        if not self.errors and not self.warnings:
            print("✅ All skills valid!")
            return True
        
        return len(self.errors) == 0
    
    def validate_skill(self, skill_dir: Path):
        """Validate a single skill"""
        skill_name = skill_dir.name
        print(f"  Checking {skill_name}...")
        
        # Check required files
        required_files = ['SKILL.md', 'README.md', 'metadata.json']
        for filename in required_files:
            if not (skill_dir / filename).exists():
                self.errors.append((skill_name, f"Missing {filename}"))
        
        # Validate metadata.json
        metadata_file = skill_dir / 'metadata.json'
        if metadata_file.exists():
            try:
                with open(metadata_file) as f:
                    metadata = json.load(f)
                
                required_fields = ['version', 'organization', 'date', 'abstract']
                for field in required_fields:
                    if field not in metadata:
                        self.errors.append((skill_name, f"metadata.json missing '{field}'"))
            except json.JSONDecodeError as e:
                self.errors.append((skill_name, f"Invalid JSON in metadata.json: {e}"))
        
        # Validate SKILL.md frontmatter
        skill_file = skill_dir / 'SKILL.md'
        if skill_file.exists():
            with open(skill_file, encoding='utf-8') as f:
                content = f.read()
            
            if not content.startswith('---'):
                self.errors.append((skill_name, "SKILL.md missing frontmatter"))
            else:
                # Check frontmatter fields
                frontmatter = content.split('---')[1]
                if 'name:' not in frontmatter:
                    self.errors.append((skill_name, "SKILL.md frontmatter missing 'name'"))
                if 'description:' not in frontmatter:
                    self.errors.append((skill_name, "SKILL.md frontmatter missing 'description'"))
        
        # Validate rules directory
        rules_dir = skill_dir / 'rules'
        if rules_dir.exists():
            self.validate_rules(skill_name, rules_dir)
        else:
            self.warnings.append((skill_name, "No rules directory found"))
        
        # Check if AGENTS.md exists (should be built)
        if not (skill_dir / 'AGENTS.md').exists():
            self.warnings.append((skill_name, "AGENTS.md not generated. Run build.py"))
    
    def validate_rules(self, skill_name: str, rules_dir: Path):
        """Validate rule files"""
        # Check for _sections.md
        if not (rules_dir / '_sections.md').exists():
            self.errors.append((skill_name, "rules/_sections.md missing"))
        
        # Check for _template.md
        if not (rules_dir / '_template.md').exists():
            self.warnings.append((skill_name, "rules/_template.md missing"))
        
        # Validate individual rules
        rule_files = [f for f in rules_dir.glob('*.md') if not f.name.startswith('_')]
        
        for rule_file in rule_files:
            self.validate_rule(skill_name, rule_file)
    
    def validate_rule(self, skill_name: str, rule_file: Path):
        """Validate a single rule file"""
        with open(rule_file, encoding='utf-8') as f:
            content = f.read()
        
        rule_id = f"{skill_name}/{rule_file.name}"
        
        # Check frontmatter
        if not content.startswith('---'):
            self.errors.append((rule_id, "Missing frontmatter"))
            return
        
        try:
            frontmatter_text = content.split('---')[1]
            
            # Required fields
            required = ['title:', 'impact:', 'tags:']
            for field in required:
                if field not in frontmatter_text:
                    self.errors.append((rule_id, f"Frontmatter missing '{field}'"))
        except IndexError:
            self.errors.append((rule_id, "Malformed frontmatter"))
            return
        
        # Check for code examples
        code_blocks = re.findall(r'```(\w+)\n', content)
        if not code_blocks:
            self.warnings.append((rule_id, "No code examples found"))
        
        # Check for "Incorrect" and "Correct" sections
        if '**Incorrect' not in content:
            self.warnings.append((rule_id, "Missing 'Incorrect' example"))
        if '**Correct' not in content:
            self.warnings.append((rule_id, "Missing 'Correct' example"))

def main():
    """Run validation"""
    skills_dir = Path(__file__).parent / 'skills'
    
    if not skills_dir.exists():
        print("❌ Skills directory not found")
        return 1
    
    validator = SkillValidator(skills_dir)
    success = validator.validate_all()
    
    return 0 if success else 1

if __name__ == '__main__':
    import sys
    sys.exit(main())
