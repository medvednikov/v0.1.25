module main

import (
	vweb
	vweb.assets
	time
)

const (
	port = 8081
)

pub struct App {
mut:
	vweb vweb.Context
}

fn main() {
	vweb.run<App>(port)
}

pub fn (app mut App) init() {
	// Arbitary mime type.
	app.vweb.serve_static('/favicon.ico', 'favicon.ico', 'img/x-icon')
	// Automatically make available known static mime types found in given directory.
	app.vweb.handle_static('assets')
	// This would make available all known static mime types from current
	// directory and below.
	//app.vweb.handle_static('.')
}

pub fn (app mut App) reset() {}

fn (app mut App) index() {
	// We can dynamically specify which assets are to be used in template.
	mut am := assets.new_manager()
	am.add_css('assets/index.css')

	css := am.include_css(false)
	title := 'VWeb Assets Example'
	subtitle := 'VWeb can serve static assets too!'
	message := 'It also has an Assets Manager that allows dynamically specifying which CSS and JS files to be used.'

	$vweb.html()
}

fn (app mut App) text() {
	app.vweb.text('Hello, world from vweb!')
}

fn (app mut App) time() {
	app.vweb.text(time.now().format())
}
