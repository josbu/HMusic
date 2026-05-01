import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

# Add popupMenuTheme right after dialogTheme
replacement = r'''dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF151E32),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF151E32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),'''

content = re.sub(r'dialogTheme: DialogThemeData\(\s*backgroundColor: const Color\(0xFF151E32\),\s*surfaceTintColor: Colors.transparent,\s*shape: RoundedRectangleBorder\(\s*borderRadius: BorderRadius.circular\(20\),\s*side: BorderSide\(color: Colors.white.withOpacity\(0.05\)\),\s*\),\s*\),', replacement, content)

with open('lib/main.dart', 'w') as f:
    f.write(content)

