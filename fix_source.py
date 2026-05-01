import re

with open('lib/presentation/pages/settings/source_settings_page.dart', 'r') as f:
    content = f.read()

# Make card transparent instead of changing structure to avoid bracket issues
content = re.sub(r'elevation: 0,\n\s*color: Theme.of\(context\).colorScheme.surfaceVariant.withOpacity\(0.3\),', r'elevation: 0,\n      color: Colors.transparent,\n      margin: EdgeInsets.zero,', content)
content = re.sub(r'elevation: 0,\n\s*color: colorScheme.surfaceVariant.withOpacity\(0.3\),', r'elevation: 0,\n      color: Colors.transparent,\n      margin: EdgeInsets.zero,', content)
content = re.sub(r'color: const Color\(0xFF151E32\),', r'color: Colors.transparent,\n      margin: EdgeInsets.zero,', content)

# Remove input borders if they exist inside BoxDecoration
content = re.sub(r'border: Border.all\(\n\s*color: Theme.of\(context\).colorScheme.outline.withOpacity\(0.5\),\n\s*\),', '', content)

with open('lib/presentation/pages/settings/source_settings_page.dart', 'w') as f:
    f.write(content)

