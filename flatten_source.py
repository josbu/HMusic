import re

with open('lib/presentation/pages/settings/source_settings_page.dart', 'r') as f:
    content = f.read()

# Replace Card with Container
content = re.sub(r'return Card\(\s*elevation: 0,\s*color: Colors.transparent,\s*margin: EdgeInsets.zero,\s*child: Padding\(', r'return Padding(', content)

with open('lib/presentation/pages/settings/source_settings_page.dart', 'w') as f:
    f.write(content)

