import re
import os

files = [
    'lib/features/home/presentation/widgets/home_ui_components.dart',
    'lib/features/home/presentation/pages/home_page.dart'
]

# Mapping hex -> AppColors equivalent
hex_map = {
    "0xFF172033": "AppColors.surfaceDark",
    "0xFFF7FAFE": "AppColors.surfaceLight",
    "0xFF1E293B": "AppColors.surfaceDarkMuted",
    "0xFFEEF2FF": "AppColors.backgroundLight",
    "0xFFD8E4F2": "AppColors.slate200",
    "0xFF0F1B37": "AppColors.textDark",
    "0xFF6B7E9A": "AppColors.textGrey",
    "0xFF35D4D3": "AppColors.accentMint",
    "0xFF30E8E8": "AppColors.accentMint",
    "0xFFFF6B35": "AppColors.deepOrange",
    "0xFF5C6BC0": "AppColors.primary",
    "0xFFFFB300": "AppColors.warning",
    "0xFF42A5F5": "AppColors.primary",
    "0xFFFF7043": "AppColors.orange",
    "0xFF6366F1": "AppColors.primary",
    "0xFF667eea": "AppColors.primary",
    "0xFF764ba2": "AppColors.purple",
    "0xFFf093fb": "AppColors.purple",
    "0xFFFBBF24": "AppColors.accentYellow",
    "0xFFF59E0B": "AppColors.orange",
    "0xFFEF4444": "AppColors.dangerGradient[0]",
    "0xFFFFF3E0": "AppColors.orange.withValues(alpha: 0.1)",
    "0xFFFEF9C3": "AppColors.accentYellow.withValues(alpha: 0.1)",
    "0xFF8B5CF6": "AppColors.purple",
    "0xFFEDE9FE": "AppColors.purple.withValues(alpha: 0.1)",
    "0xFFDBEAFE": "AppColors.primary.withValues(alpha: 0.1)",
    "0xFF3B82F6": "AppColors.primary",
    "0xFF10B981": "AppColors.greenSuccessBright",
    "0xFFD1FAE5": "AppColors.greenSuccessSoft.withValues(alpha: 0.1)",
    "0xFFA7F3D0": "AppColors.greenSuccessSoft.withValues(alpha: 0.2)",
    "0xFFBFDBFE": "AppColors.primary.withValues(alpha: 0.2)",
    "0xFF059669": "AppColors.greenSuccess",
    "0xFF065F46": "AppColors.greenSuccess",
    "0xFF1E40AF": "AppColors.primaryDark",
    "0xFFD97706": "AppColors.orange",
    "0xFF34D399": "AppColors.greenSuccessSoft",
    "0xFFF97316": "AppColors.orange",
    "0xFFFEF2F2": "AppColors.dangerGradient[0].withValues(alpha: 0.1)",
    "0xFFF5F3FF": "AppColors.purple.withValues(alpha: 0.1)",
    "0xFF0EA5E9": "AppColors.primary",
    "0xFFE0F2FE": "AppColors.primary.withValues(alpha: 0.1)",
    "0xFF43E97B": "AppColors.greenSuccessBright",
    "0xFFE8FFF0": "AppColors.greenSuccess.withValues(alpha: 0.1)",
    "0xFFFFF7ED": "AppColors.warning.withValues(alpha: 0.1)",
}

def clean_const_box_decoration(text):
    # If the text has `const BoxDecoration(...)` and inside there are non-const features like `.withValues`
    # or `foo[0]`. Only replace the 'const ' of BoxDecoration. This is slightly generic but helpful.
    # We will just replace it line-by-line if there is `const BoxDecoration` and `.withValues`.
    lines = text.split('\n')
    for i in range(len(lines)):
        if "BoxDecoration(" in lines[i]:
            # if we see a color that has 'withValues' or '[0]' nearby, we can strip const.
            # Actually, I'll just strip 'const ' from 'const BoxDecoration' if 'withValues' or 'dangerGradient' appears anywhere until ')' 
            pass
    return text

for fp in files:
    if os.path.exists(fp):
        with open(fp, 'r') as f:
            content = f.read()
            
        original = content
        
        # Replace `const Color(0x...)` and `Color(0x...)` 
        # Using regex to find optional `const ` followed by `Color(0xHEX)`
        def replacer(match):
            has_const = match.group(1) is not None
            hex_val = match.group(2)
            
            replacement = hex_map.get(hex_val)
            if not replacement:
                # keep as is
                return match.group(0)
            
            # if replacement has .withValues or array bracket `[0]`, we CANNOT have `const` anywhere before it 
            # (unless it's complex, but it's safe to strip `const ` from the color itself).
            if has_const and ".withValues" not in replacement and "[" not in replacement:
                # If we were using const Color(...) and replacement is plain AppColors.something,
                # It is technically already a const value, so `const AppColors.something` is illegal dart syntax!
                # Dart requires `const` for creating INSTANCES, but `AppColors.xx` is a static field.
                # So we simply never need the `const ` in front of it!
                return replacement
            
            return replacement

        content = re.sub(r'(const\s+)?Color\((0xFF[0-9a-fA-F]{6})\)', replacer, content)

        # Let's fix specific invalid const BoxDecorations or arrays from the replacements:
        # e.g. `const BoxDecoration( ... color: AppColors.dangerGradient[0] )` -> `BoxDecoration( ... color: AppColors.dangerGradient[0] )`
        # Because re.DOTALL is very dangerous, let's fix known ones:
        content = content.replace("const BoxDecoration(\n                          color: AppColors.dangerGradient[0],", 
                                  "BoxDecoration(\n                          color: AppColors.dangerGradient[0],")
                                  
        # Add imports if changed
        if content != original:
            import_stmt = "import 'package:lexilingo_app/core/theme/app_theme.dart';"
            if import_stmt not in content:
                last_import = content.rfind("import '")
                if last_import != -1:
                    end_of_line = content.find(";", last_import) + 1
                    content = content[:end_of_line] + "\n" + import_stmt + content[end_of_line:]
            
            with open(fp, 'w') as f:
                f.write(content)
            print(f"Updated {fp}")

