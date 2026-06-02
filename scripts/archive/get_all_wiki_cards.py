import json
import subprocess

def get_wiki_cards(offset=0):
    cmd = ['mcp_hyperon-wiki_search_cards', '--query', 'RawData+opencog-ml', '--offset', str(offset), '--limit', '100']
    # I can't run mcp tools from python directly.
    # I will have to do it in turns.
    pass

# I'll just use the search results I already have or fetch them in turns.
# Since I have 1279, I'll need 13 turns.
# I'll try to find a better way.
