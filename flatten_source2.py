import re

with open('lib/presentation/pages/settings/source_settings_page.dart', 'r') as f:
    content = f.read()

content = re.sub(r'return Card\(\s*elevation: 0,\s*color: colorScheme.surfaceVariant.withOpacity\(0.3\),\s*child: Padding\(', r'return Padding(', content)
content = re.sub(r'color: colorScheme.primary.withOpacity\(0.1\),\s*borderRadius: BorderRadius.circular\(8\),\s*', r'', content)

with open('lib/presentation/pages/settings/source_settings_page.dart', 'w') as f:
    f.write(content)

