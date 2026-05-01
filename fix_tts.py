import re

with open('lib/presentation/pages/settings/tts_settings_page.dart', 'r') as f:
    content = f.read()

# Replace any Card coloring or elevation
content = re.sub(r'elevation: 0,\n\s*color: [^,]+,', r'elevation: 0,\n      color: Colors.transparent,\n      margin: EdgeInsets.zero,', content)
content = re.sub(r'color: const Color\(0xFF151E32\),', r'color: Colors.transparent,\n      margin: EdgeInsets.zero,', content)

# Check for BoxDecorations with backgrounds
content = re.sub(r'decoration: BoxDecoration\([^)]*color:[^)]*\),', '', content)

with open('lib/presentation/pages/settings/tts_settings_page.dart', 'w') as f:
    f.write(content)

