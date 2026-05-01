import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

# Fix bottomSheetTheme
content = re.sub(r'bottomSheetTheme: BottomSheetThemeData\(\s*backgroundColor: darkScheme.surface,\s*surfaceTintColor: Colors.transparent,\s*shape: const RoundedRectangleBorder\(\s*borderRadius: BorderRadius.vertical\(top: Radius.circular\(20\)\),\s*\),',
r'''bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFF151E32),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),''', content)

# Fix dialogTheme
content = re.sub(r'dialogTheme: DialogThemeData\(\s*backgroundColor: darkScheme.surface,\s*surfaceTintColor: Colors.transparent,\s*shape: RoundedRectangleBorder\(\s*borderRadius: BorderRadius.circular\(20\),\s*\),',
r'''dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF151E32),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),''', content)


with open('lib/main.dart', 'w') as f:
    f.write(content)

