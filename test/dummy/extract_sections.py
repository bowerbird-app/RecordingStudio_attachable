import re
with open('/root/.vscode-remote/data/User/workspaceStorage/-3fa0f216-2/GitHub.copilot-chat/chat-session-resources/a25e0596-6d72-4ed4-b4b8-9710bd4143ad/call_MHw2eGFQcDRWM0JjY28ySUhoTWw__vscode-1777939014553/content.txt', 'r') as f:
    content = f.read()

def extract_li(title, content):
    match = re.search(f"{title}.*?<ul>(.*?)</ul>", content, re.DOTALL | re.IGNORECASE)
    if match:
        li_match = re.search(r"<li.*?>(.*?)</li>", match.group(1), re.DOTALL)
        if li_match:
            return li_match.group(1).strip()
    return "Not found"

print("Prerequisites:", extract_li("Prerequisites", content))
print("Verify Active Storage wiring:", extract_li("Verify Active Storage wiring", content))
print("Next checks:", extract_li("Next checks", content))
