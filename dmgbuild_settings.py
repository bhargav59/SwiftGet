# dmgbuild settings for SwiftGet.dmg
# https://dmgbuild.readthedocs.io/

import os

# Basic metadata
application = defines.get('app', 'export/SwiftGet.app')
appname = os.path.basename(application)

# DMG window appearance
format = defines.get('format', 'UDZO')         # Zlib-compressed
size = defines.get('size', None)

files = [application]
symlinks = {'Applications': '/Applications'}

icon_locations = {
    appname:       (130, 180),
    'Applications': (390, 180),
}

background = 'builtin-arrow'

window_rect = ((200, 120), (540, 380))
icon_size = 96
text_size = 13
