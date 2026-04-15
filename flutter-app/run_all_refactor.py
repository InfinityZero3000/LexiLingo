import re
import os
import glob

# Find all dart files
files = []
for root, _, filenames in os.walk('lib/features'):
    for filename in filenames:
        if filename.endswith('.dart'):
            files.append(os.path.join(root, filename))

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
    "0xFF1A1A1A": "AppColors.textDark",
}

for fp in files:
    with open(fp, 'r') as f:
        content = f.read()
        
    original = content
    
    def replacer(match):
        has_const = match.group(1) is not None
        hex_val = match.group(2)
        
        replacement = hex_map.get(hex_val)
        if not replacement:
            return match.group(0)
        
        if has_const and ".withValues" not in replacement and "[" not in replacement:
            return replacement
        
        return replacement

    content = re.sub(r'(const\s+)?Color\((0xFF[0-9a-fA-F]{6})\)', replacer, content)

    if content != original:
        import_stmt = "import 'package:lexilingo_app/core/theme/app_theme.dart';"
        if import_stmt not in content:
            last_import = content.rfind("import '")
            if last_import != -1:
                end_of_line = content.find(";", last_import) + 1
                content = content[:end_of_line] + "\n" + import_stmt + content[end_of_line:]
            else:
                content = import_stmt + "\n" + content
        
        with open(fp, 'w') as f:
            f.write(content)
        print(f"Updated {fp}")
