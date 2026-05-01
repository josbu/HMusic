import re

with open('lib/presentation/pages/settings/source_settings_page.dart', 'r') as f:
    content = f.read()

# Replace the Card and color logic
new_card = """  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF21B0A5).withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected ? Border.all(color: const Color(0xFF21B0A5).withOpacity(0.3)) : Border.all(color: Colors.transparent),
      ),
      child: ListTile("""

content = re.sub(r'\)\s*{\s*return Card\(\s*margin: const EdgeInsets\.only\(bottom: 8\),\s*elevation: isSelected \? 2 : 0,\s*color:\s*isSelected\s*\?\s*Theme.of\(context\).colorScheme.primaryContainer.withOpacity\(0\.3\)\s*:\s*Theme.of\(context\).colorScheme.surface,\s*child: ListTile\(', new_card, content)

with open('lib/presentation/pages/settings/source_settings_page.dart', 'w') as f:
    f.write(content)

