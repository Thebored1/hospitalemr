import re

path = r'backend\portal\templates\portal\agents\assignment_detail.html'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the Status <th> header
content = content.replace('<th>Status</th>', '')

# Remove the Status <td> cell block
content = re.sub(
    r'\s*<td>\s*<span class="badge bg-info">\{\{ doctor\.status \}\}</span>\s*</td>',
    '',
    content
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")
