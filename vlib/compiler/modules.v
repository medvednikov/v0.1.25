// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module compiler

import (
	os
	v.pref
)

pub const (
	v_modules_path = pref.default_module_path
)
// Holds import information scoped to the parsed file
struct ImportTable {
mut:
	imports        map[string]string // alias => module
	used_imports   []string // alias
	import_tok_idx map[string]int // module => idx
}
// Once we have a module format we can read from module file instead
// this is not optimal
fn (table &Table) qualify_module(mod string, file_path string) string {
	for m in table.imports {
		if m.contains('.') && m.contains(mod) {
			m_parts := m.split('.')
			m_path := m_parts.join(os.path_separator)
			if mod == m_parts[m_parts.len - 1] && file_path.contains(m_path) {
				return m
			}
		}
	}
	return mod
}

fn new_import_table() ImportTable {
	return ImportTable{
		imports: map[string]string
	}
}

fn (p mut Parser) register_import(mod string, tok_idx int) {
	p.register_import_alias(mod, mod, tok_idx)
}

fn (p mut Parser) register_import_alias(alias string, mod string, tok_idx int) {
	// NOTE: come back here
	// if alias in it.imports && it.imports[alias] == mod {}
	if alias in p.import_table.imports && p.import_table.imports[alias] != mod {
		p.error('cannot import $mod as $alias: import name $alias already in use')
	}
	if mod.contains('.internal.') && !p.is_vgen {
		mod_parts := mod.split('.')
		mut internal_mod_parts := []string
		for part in mod_parts {
			if part == 'internal' {
				break
			}
			internal_mod_parts << part
		}
		internal_parent := internal_mod_parts.join('.')
		if !p.mod.starts_with(internal_parent) {
			p.error('module $mod can only be imported internally by libs')
		}
	}
	p.import_table.imports[alias] = mod
	p.import_table.import_tok_idx[mod] = tok_idx
}

fn (it &ImportTable) get_import_tok_idx(mod string) int {
	return it.import_tok_idx[mod]
}

fn (it &ImportTable) known_import(mod string) bool {
	return mod in it.imports || it.is_aliased(mod)
}

fn (it &ImportTable) known_alias(alias string) bool {
	return alias in it.imports
}

fn (it &ImportTable) is_aliased(mod string) bool {
	for _, val in it.imports {
		if val == mod {
			return true
		}
	}
	return false
}

fn (it &ImportTable) resolve_alias(alias string) string {
	return it.imports[alias]
}

fn (it mut ImportTable) register_used_import(alias string) {
	if !(alias in it.used_imports) {
		it.used_imports << alias
	}
}

fn (it &ImportTable) is_used_import(alias string) bool {
	return alias in it.used_imports
}

// should module be accessable
pub fn (p &Parser) is_mod_in_scope(mod string) bool {
	mut mods_in_scope := ['', 'builtin', 'main', p.mod]
	for _, m in p.import_table.imports {
		mods_in_scope << m
	}
	return mod in mods_in_scope
}

// return resolved dep graph (order deps)
pub fn (v &V) resolve_deps() &DepGraph {
	graph := v.import_graph()
	deps_resolved := graph.resolve()
	if !deps_resolved.acyclic {
		verror('import cycle detected between the following modules: \n' + deps_resolved.display_cycles())
	}
	return deps_resolved
}

// graph of all imported modules
pub fn (v &V) import_graph() &DepGraph {
	mut graph := new_dep_graph()
	for p in v.parsers {
		mut deps := []string
		for _, m in p.import_table.imports {
			deps << m
		}
		graph.add(p.mod, deps)
	}
	return graph
}

// get ordered imports (module speficic dag method)
pub fn (graph &DepGraph) imports() []string {
	mut mods := []string
	for node in graph.nodes {
		mods << node.name
	}
	return mods
}

[inline]
fn (v &V) module_path(mod string) string {
	// submodule support
	return mod.replace('.', os.path_separator)
}

// 'strings' => 'VROOT/vlib/strings'
// 'installed_mod' => '~/.vmodules/installed_mod'
// 'local_mod' => '/path/to/current/dir/local_mod'
fn (v mut V) set_module_lookup_paths() {
	// Module search order:
	// 0) V test files are very commonly located right inside the folder of the
	// module, which they test. Adding the parent folder of the module folder
	// with the _test.v files, *guarantees* that the tested module can be found
	// without needing to set custom options/flags.
	// 1) search in the *same* directory, as the compiled final v program source
	// (i.e. the . in `v .` or file.v in `v file.v`)
	// 2) search in the modules/ in the same directory.
	// 3) search in the provided paths
	// By default, these are what (3) contains:
	// 3.1) search in vlib/
	// 3.2) search in ~/.vmodules/ (i.e. modules installed with vpm)
	v.module_lookup_paths = []
	if v.pref.is_test {
		v.module_lookup_paths << os.base_dir(v.compiled_dir) // pdir of _test.v
	}
	v.module_lookup_paths << v.compiled_dir
	x := os.join_path(v.compiled_dir, 'modules')
	if v.pref.verbosity.is_higher_or_equal(.level_two) {
		println('x: "$x"')
	}
	v.module_lookup_paths << os.join_path(v.compiled_dir, 'modules')
	v.module_lookup_paths << v.pref.lookup_path
	if v.pref.verbosity.is_higher_or_equal(.level_two) {
		v.log('v.module_lookup_paths') //: $v.module_lookup_paths')
		println(v.module_lookup_paths)
	}
}

fn (p mut Parser) find_module_path(mod string) ?string {
	vmod_file_location := p.v.mod_file_cacher.get( p.file_path_dir )
	mut module_lookup_paths := []string
	if vmod_file_location.vmod_file.len != 0 {
		if ! vmod_file_location.vmod_folder in p.v.module_lookup_paths {
			module_lookup_paths << vmod_file_location.vmod_folder
		}
	}
	module_lookup_paths << p.v.module_lookup_paths

	mod_path := p.v.module_path(mod)
	for lookup_path in module_lookup_paths {
		try_path := os.join_path(lookup_path, mod_path)
		if p.v.pref.verbosity.is_higher_or_equal(.level_three) {
			println('  >> trying to find $mod in $try_path ...')
		}
		if os.is_dir(try_path) {
			if p.v.pref.verbosity.is_higher_or_equal(.level_three) {
				println('  << found $try_path .')
			}
			return try_path
		}
	}
	return error('module "$mod" not found in ${module_lookup_paths}')
}

[inline]
fn mod_gen_name(mod string) string {
	return mod.replace('.', '_dot_')
}

[inline]
fn mod_gen_name_rev(mod string) string {
	return mod.replace('_dot_', '.')
}
