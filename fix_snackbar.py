import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

replacement = r'''snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF090E17),
          contentTextStyle: const TextStyle(color: Colors.white),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        ),'''

content = re.sub(r'snackBarTheme: SnackBarThemeData\(\s*behavior: SnackBarBehavior\.floating,\s*backgroundColor: const Color\(0xFF090E17\),\s*contentTextStyle: const TextStyle\(color: Colors\.white\),\s*insetPadding: const EdgeInsets\.symmetric\(horizontal: 16, vertical: 8\),\s*elevation: 8,\s*shape: RoundedRectangleBorder\(\s*borderRadius: BorderRadius\.circular\(12\),\s*\),\s*\),', replacement, content)

with open('lib/main.dart', 'w') as f:
    f.write(content)

