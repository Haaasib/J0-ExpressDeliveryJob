fx_version 'cerulean'
game 'rdr3'
author 'mfhasib'
description 'J0-ExpressDeliveryJob'
version '1.0.0'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

shared_scripts {
	'@jo_libs/init.lua',
	'shared/shared.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    'server/*.lua'
}

ui_page 'html/index.html'

files {
	'html/index.html',
	'html/style.css',
	'html/images/*.png',
	'html/images/*.jpg',
	'html/images/*.webp',
	'html/images/*.svg',
	'html/fonts/*.ttf',	
	'html/fonts/*.otf',	
	'html/script.js',
	'html/*png',
	'html/*jpg',
	'html/*webp',
	'html/images/*.gif'
}

jo_libs {
	'callback',
	'framework',
	'entity',
	'ui',

}

lua54 'yes'
this_is_a_map 'yes'


escrow_ignore {
    'shared/shared.lua'
}