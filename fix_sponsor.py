import re

with open('lib/presentation/pages/settings/sponsor_page.dart', 'r') as f:
    content = f.read()

# Remove the entire decoration block from the Thank You card
content = re.sub(r'decoration: BoxDecoration\([^)]+boxShadow: \[[^\]]+\](?:,\n\s*)?\),', '', content, flags=re.DOTALL)
content = re.sub(r'gradient: LinearGradient\([\s\S]*?end: Alignment.bottomRight,\n\s*\),', '', content)
content = re.sub(r'border: Border.all\([\s\S]*?width: 1,\n\s*\),', '', content)
content = re.sub(r'boxShadow: \[\s*BoxShadow\([\s\S]*?offset: const Offset\(0, 4\),\n\s*\),\n\s*\],', '', content)
# Just clean out the first BoxDecoration completely:
content = re.sub(r'decoration: BoxDecoration\(\s*borderRadius: BorderRadius.circular\(16\),\s*\),', '', content)

# Second block (QR Code):
# color: const Color(0xFF151E32),
content = content.replace('color: const Color(0xFF151E32),', '')
# border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
content = re.sub(r'border: Border.all\(color: colorScheme.outline.withOpacity\(0.2\)\),', '', content)
# boxShadow: [ ... ],
content = re.sub(r'boxShadow: \[\s*BoxShadow\([\s\S]*?offset: const Offset\(0, 1\),\n\s*\),\n\s*\],', '', content)

# Notice block:
content = re.sub(r'color: colorScheme.primary.withOpacity\(0.1\),', '', content)
content = re.sub(r'border: Border.all\(color: colorScheme.primary.withOpacity\(0.2\)\),', '', content)


with open('lib/presentation/pages/settings/sponsor_page.dart', 'w') as f:
    f.write(content)

