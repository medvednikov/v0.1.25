module doc

import (
	strings
	// v.builder
	v.pref
	v.table
	v.parser
	v.ast
	os
)

struct Doc {
	out   strings.Builder
	table &table.Table
	mod   string
mut:
	stmts []ast.Stmt // all module statements from all files
}

type FilterFn fn(node ast.FnDecl)bool

pub fn doc(mod string, table &table.Table) string {
	mut d := Doc{
		out: strings.new_builder(1000)
		table: table
		mod: mod
	}
	vlib_path := os.dir(pref.vexe_path()) + '/vlib'
	mod_path := mod.replace('.', os.path_separator)
	path := os.join_path(vlib_path,mod_path)
	if !os.exists(path) {
		println('module "$mod" not found')
		println(path)
		return ''
	}
	// vfiles := os.walk_ext(path, '.v')
	files := os.ls(path) or {
		panic(err)
	}
	for file in files {
		if !file.ends_with('.v') {
			continue
		}
		if file.ends_with('_test.v') || file.ends_with('_windows.v') || file.ends_with('_macos.v') {
			continue
		}
		file_ast := parser.parse_file(os.join_path(path,file), table, .skip_comments,	&pref.Preferences{})
		d.stmts << file_ast.stmts
	}
	if d.stmts.len == 0 {
		println('nothing here')
		exit(1)
	}
	d.print_structs()
	d.print_enums()
	d.print_fns()
	d.out.writeln('')
	d.print_methods()
	/*
		for stmt in file_ast.stmts {
			d.stmt(stmt)
		}
	println(path)
	*/

	return d.out.str().trim_space()
}

fn (d &Doc) get_fn_node(f ast.FnDecl) string {
	return f.str(d.table).replace_each([d.mod + '.', '', 'pub ', ''])
}

fn (d mut Doc) print_fns() {
	fn_signatures := d.get_fn_signatures(is_pub_function)
	d.write_fn_signatures(fn_signatures)
}

fn (d mut Doc) print_methods() {
	fn_signatures := d.get_fn_signatures(is_pub_method)
	d.write_fn_signatures(fn_signatures)
}

[inline]
fn (d mut Doc) write_fn_signatures(fn_signatures []string) {
	for s in fn_signatures {
		d.out.writeln(s)
	}
}

fn (d Doc) get_fn_signatures(filter_fn FilterFn) []string {
	mut fn_signatures := []string
	for stmt in d.stmts {
		match stmt {
			ast.FnDecl {
				if filter_fn(it) {
					fn_signatures << d.get_fn_node(it)
				}
			}
			else {}
	}
	}
	fn_signatures.sort()
	return fn_signatures
}

fn is_pub_method(node ast.FnDecl) bool {
	return node.is_pub && node.is_method && !node.is_deprecated
}

fn is_pub_function(node ast.FnDecl) bool {
	return node.is_pub && !node.is_method && !node.is_deprecated
}

// TODO it's probably better to keep using AST, not `table`
fn (d mut Doc) print_enums() {
	for typ in d.table.types {
		if typ.kind != .enum_ {
			continue
		}
		d.out.writeln('enum $typ.name {')
		info := typ.info as table.Enum
		for val in info.vals {
			d.out.writeln('\t$val')
		}
		d.out.writeln('}')
	}
}

fn (d mut Doc) print_structs() {
	for typ in d.table.types {
		if typ.kind != .struct_ || !typ.name.starts_with(d.mod + '.') {
			// !typ.name[0].is_capital() || typ.name.starts_with('C.') {
			continue
		}
		name := typ.name.after('.')
		d.out.writeln('struct $name {')
		info := typ.info as table.Struct
		for field in info.fields {
			sym := d.table.get_type_symbol(field.typ)
			d.out.writeln('\t$field.name $sym.name')
		}
		d.out.writeln('}\n')
	}
}
