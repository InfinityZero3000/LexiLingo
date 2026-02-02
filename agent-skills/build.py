#!/usr/bin/env python3
"""
Build script to compile individual rule files into AGENTS.md
Similar to Vercel's agent-skills build system
"""

import os
import json
import re
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass
from datetime import datetime

@dataclass
class CodeExample:
    label: str
    description: Optional[str]
    code: str
    language: str
    additional_text: Optional[str] = None

@dataclass
class Rule:
    id: str
    title: str
    section: int
    impact: str
    impact_description: Optional[str]
    explanation: str
    examples: List[CodeExample]
    references: List[str]
    tags: List[str]

@dataclass
class Section:
    number: int
    title: str
    impact: str
    description: Optional[str]
    rules: List[Rule]

class SkillBuilder:
    def __init__(self, skill_dir: Path):
        self.skill_dir = skill_dir
        self.rules_dir = skill_dir / 'rules'
        self.metadata_file = skill_dir / 'metadata.json'
        self.output_file = skill_dir / 'AGENTS.md'
        
        # Load metadata
        with open(self.metadata_file, 'r', encoding='utf-8') as f:
            self.metadata = json.load(f)
        
        # Load sections
        self.sections_map = self.load_sections()
    
    def load_sections(self) -> Dict[str, tuple]:
        """Load section definitions from _sections.md"""
        sections_file = self.rules_dir / '_sections.md'
        sections = {}
        
        with open(sections_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Parse sections with regex
        pattern = r'## (\d+)\. (.*?) \((.*?)\)\s*\*\*Impact:\*\* (.*?)\s*\*\*Description:\*\* (.*?)(?=##|\Z)'
        matches = re.findall(pattern, content, re.DOTALL)
        
        for match in matches:
            number, title, prefix, impact, description = match
            sections[prefix.strip()] = (
                int(number),
                title.strip(),
                impact.strip(),
                description.strip()
            )
        
        return sections
    
    def parse_rule_file(self, file_path: Path) -> Optional[Rule]:
        """Parse a single rule markdown file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract frontmatter
        frontmatter_match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)', content, re.DOTALL)
        if not frontmatter_match:
            print(f"⚠️  Skipping {file_path.name}: No frontmatter found")
            return None
        
        frontmatter_text, body = frontmatter_match.groups()
        
        # Parse frontmatter
        frontmatter = {}
        for line in frontmatter_text.split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                frontmatter[key.strip()] = value.strip()
        
        # Determine section from filename prefix
        filename = file_path.stem
        prefix = filename.split('-')[0]
        
        if prefix not in self.sections_map:
            print(f"⚠️  Unknown section prefix '{prefix}' in {file_path.name}")
            return None
        
        section_num, _, _, _ = self.sections_map[prefix]
        
        # Parse code examples from body
        examples = self.extract_examples(body)
        
        # Extract references
        references = re.findall(r'Reference: \[(.*?)\]\((.*?)\)', body)
        reference_urls = [url for _, url in references]
        
        # Parse tags
        tags = [t.strip() for t in frontmatter.get('tags', '').split(',') if t.strip()]
        
        return Rule(
            id=filename,
            title=frontmatter.get('title', 'Untitled'),
            section=section_num,
            impact=frontmatter.get('impact', 'MEDIUM'),
            impact_description=frontmatter.get('impactDescription'),
            explanation=self.extract_explanation(body),
            examples=examples,
            references=reference_urls,
            tags=tags
        )
    
    def extract_explanation(self, body: str) -> str:
        """Extract the main explanation before code examples"""
        # Get text before first code block or "Incorrect" section
        match = re.search(r'## .*?\n\n(.*?)(?=\*\*Incorrect|\*\*Why this is)', body, re.DOTALL)
        if match:
            return match.group(1).strip()
        return ""
    
    def extract_examples(self, body: str) -> List[CodeExample]:
        """Extract code examples from markdown body"""
        examples = []
        
        # Pattern: **Label (description):** followed by code block
        pattern = r'\*\*(Incorrect|Correct|Example)(.*?):\*\*\s*\n\n```(\w+)\n(.*?)\n```'
        matches = re.findall(pattern, body, re.DOTALL)
        
        for label, desc, lang, code in matches:
            description = desc.strip('() ') if desc else None
            
            # Extract "Why this is..." text after code block
            additional = self.extract_additional_text(body, code)
            
            examples.append(CodeExample(
                label=label,
                description=description,
                code=code.strip(),
                language=lang,
                additional_text=additional
            ))
        
        return examples
    
    def extract_additional_text(self, body: str, code: str) -> Optional[str]:
        """Extract explanation text after a code block"""
        # Find the code block and get text after it until next ** or ##
        escaped_code = re.escape(code[:50])  # First 50 chars to find it
        pattern = f'{escaped_code}.*?```\s*\n\n(.*?)(?=\*\*|##|\Z)'
        match = re.search(pattern, body, re.DOTALL)
        
        if match:
            text = match.group(1).strip()
            # Only return if it starts with "Why" or similar explanatory text
            if text and any(text.startswith(w) for w in ['Why', 'This', 'The', 'Note:']):
                return text
        
        return None
    
    def build(self):
        """Build AGENTS.md from all rule files"""
        print(f"\n🔨 Building {self.skill_dir.name}...")
        print(f"   Rules directory: {self.rules_dir}")
        print(f"   Output file: {self.output_file}")
        
        # Read all rule files
        rule_files = [
            f for f in self.rules_dir.glob('*.md')
            if not f.name.startswith('_')
        ]
        
        print(f"   Found {len(rule_files)} rule files")
        
        # Parse rules
        rules = []
        for file_path in rule_files:
            rule = self.parse_rule_file(file_path)
            if rule:
                rules.append(rule)
        
        # Group by section
        sections = {}
        for rule in rules:
            if rule.section not in sections:
                prefix = rule.id.split('-')[0]
                _, title, impact, desc = self.sections_map[prefix]
                sections[rule.section] = Section(
                    number=rule.section,
                    title=title,
                    impact=impact,
                    description=desc,
                    rules=[]
                )
            sections[rule.section].rules.append(rule)
        
        # Sort sections and rules
        sorted_sections = sorted(sections.values(), key=lambda s: s.number)
        for section in sorted_sections:
            section.rules.sort(key=lambda r: r.title)
        
        # Generate markdown
        markdown = self.generate_markdown(sorted_sections)
        
        # Write output
        with open(self.output_file, 'w', encoding='utf-8') as f:
            f.write(markdown)
        
        print(f"   ✅ Built AGENTS.md with {len(sorted_sections)} sections and {len(rules)} rules\n")
    
    def generate_markdown(self, sections: List[Section]) -> str:
        """Generate the complete AGENTS.md content"""
        md = f"# {self.metadata.get('organization', 'LexiLingo')} - {self.skill_dir.name.replace('-', ' ').title()}\n\n"
        md += f"**Version {self.metadata['version']}**  \n"
        md += f"{self.metadata.get('organization', 'LexiLingo Team')}  \n"
        md += f"{self.metadata['date']}\n\n"
        
        md += "> **Note:**  \n"
        md += "> This document is mainly for agents and LLMs to follow when maintaining,  \n"
        md += "> generating, or refactoring code. Humans may also find it useful, but guidance  \n"
        md += "> here is optimized for automation and consistency by AI-assisted workflows.\n\n"
        
        md += "---\n\n"
        md += "## Abstract\n\n"
        md += f"{self.metadata['abstract']}\n\n"
        md += "---\n\n"
        
        # Table of Contents
        md += "## Table of Contents\n\n"
        for section in sections:
            md += f"{section.number}. [{section.title}](##{section.number}-{section.title.lower().replace(' ', '-')})\n"
        md += "\n---\n\n"
        
        # Sections
        for section in sections:
            md += f"## {section.number}. {section.title}\n\n"
            md += f"**Impact: {section.impact}**\n\n"
            if section.description:
                md += f"{section.description}\n\n"
            
            # Rules
            for idx, rule in enumerate(section.rules, 1):
                rule_num = f"{section.number}.{idx}"
                md += f"### {rule_num} {rule.title}\n\n"
                md += f"**Impact: {rule.impact}"
                if rule.impact_description:
                    md += f" ({rule.impact_description})"
                md += "**\n\n"
                
                md += f"{rule.explanation}\n\n"
                
                # Examples
                for example in rule.examples:
                    if example.description:
                        md += f"**{example.label}: {example.description}**\n\n"
                    else:
                        md += f"**{example.label}:**\n\n"
                    
                    md += f"```{example.language}\n"
                    md += f"{example.code}\n"
                    md += f"```\n\n"
                    
                    if example.additional_text:
                        md += f"{example.additional_text}\n\n"
                
                # References
                if rule.references:
                    md += "Reference: "
                    md += " | ".join([f"[{ref}]({ref})" for ref in rule.references])
                    md += "\n\n"
            
            md += "---\n\n"
        
        # References section
        if 'references' in self.metadata and self.metadata['references']:
            md += "## References\n\n"
            for idx, ref in enumerate(self.metadata['references'], 1):
                md += f"{idx}. [{ref}]({ref})\n"
        
        return md

def main():
    """Build all skills or a specific skill"""
    import sys
    
    # Get base directory
    base_dir = Path(__file__).parent / 'skills'
    
    # If argument provided, build specific skill
    if len(sys.argv) > 1:
        skill_name = sys.argv[1]
        skill_dir = base_dir / skill_name
        
        if not skill_dir.exists():
            print(f"❌ Skill directory not found: {skill_dir}")
            sys.exit(1)
        
        builder = SkillBuilder(skill_dir)
        builder.build()
    else:
        # Build all skills
        skill_dirs = [d for d in base_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
        
        print(f"🚀 Building {len(skill_dirs)} skills...\n")
        
        for skill_dir in skill_dirs:
            try:
                builder = SkillBuilder(skill_dir)
                builder.build()
            except Exception as e:
                print(f"❌ Error building {skill_dir.name}: {e}\n")
        
        print("✅ All skills built successfully!")

if __name__ == '__main__':
    main()
