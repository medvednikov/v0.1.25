// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module parser

import (
	v.scanner
	v.ast
	v.token
	v.table
	v.pref
	term
	os
	// runtime
	// sync
	// time
)

const (
	colored_output = term.can_show_color_on_stderr()
)

struct Parser {
	scanner     &scanner.Scanner
	file_name   string
mut:
	tok         token.Token
	peek_tok    token.Token
	// vars []string
	table       &table.Table
	is_c        bool
	// prefix_parse_fns []PrefixParseFn
	inside_if   bool
	pref        &pref.Preferences // Preferences shared from V struct
	builtin_mod bool
	mod         string
	attr        string
	expr_mod    string
	scope       &ast.Scope
	imports     map[string]string
	ast_imports []ast.Import
	is_amp      bool
	returns     bool
}

// for tests
pub fn parse_stmt(text string, table &table.Table, scope &ast.Scope) ast.Stmt {
	s := scanner.new_scanner(text, .skip_comments)
	mut p := Parser{
		scanner: s
		table: table
		pref: &pref.Preferences{}
		scope: scope
		// scope: &ast.Scope{start_pos: 0, parent: 0}
		
	}
	p.init_parse_fns()
	p.read_first_token()
	return p.stmt()
}

pub fn parse_file(path string, table &table.Table, comments_mode scanner.CommentsMode, pref &pref.Preferences) ast.File {
	// println('parse_file("$path")')
	// text := os.read_file(path) or {
	// panic(err)
	// }
	mut stmts := []ast.Stmt
	mut p := Parser{
		// scanner: scanner.new_scanner(text, comments_mode)
		scanner: scanner.new_scanner_file(path, comments_mode)
		table: table
		file_name: path
		pref: pref // &pref.Preferences{}
		
		scope: &ast.Scope{
			start_pos: 0
			parent: 0
		}
		// comments_mode: comments_mode
		
	}
	p.read_first_token()
	// p.scope = &ast.Scope{start_pos: p.tok.position(), parent: 0}
	// module decl
	module_decl := if p.tok.kind == .key_module { p.module_decl() } else { ast.Module{name: 'main'
	} }
	p.mod = module_decl.name
	p.builtin_mod = p.mod == 'builtin'
	// imports
	/*
	mut imports := []ast.Import
	for p.tok.kind == .key_import {
		imports << p.import_stmt()
	}
	*/
	// TODO: import only mode
	for {
		// res := s.scan()
		if p.tok.kind == .eof {
			// println('EOF, breaking')
			break
		}
		// println('stmt at ' + p.tok.str())
		stmts << p.top_stmt()
	}
	// println('nr stmts = $stmts.len')
	// println(stmts[0])
	p.scope.end_pos = p.tok.pos
	return ast.File{
		path: path
		mod: module_decl
		imports: p.ast_imports
		stmts: stmts
		scope: p.scope
	}
}

/*
struct Queue {
mut:
	idx              int
	mu               sync.Mutex
	paths            []string
	table            &table.Table
	parsed_ast_files []ast.File
}

fn (q mut Queue) run() {
	q.mu.lock()
	idx := q.idx
	if idx >= q.paths.len {
		q.mu.unlock()
		return
	}
	q.idx++
	q.mu.unlock()
	path := q.paths[idx]
	file := parse_file(path, q.table, .skip_comments)
	q.mu.lock()
	q.parsed_ast_files << file
	q.mu.unlock()
}
*/


pub fn parse_files(paths []string, table &table.Table, pref &pref.Preferences) []ast.File {
	/*
	println('\n\n\nparse_files()')
	println(paths)
	nr_cpus := runtime.nr_cpus()
	println('nr_cpus= $nr_cpus')
	mut q := &Queue{
		paths: paths
		table: table
	}
	for i in 0 .. nr_cpus {
		go q.run()
	}
	time.sleep_ms(100)
	return q.parsed_ast_files
	*/

	// ///////////////
	mut files := []ast.File
	for path in paths {
		// println('parse_files $path')
		files << parse_file(path, table, .skip_comments, pref)
	}
	return files
}

pub fn (p &Parser) init_parse_fns() {
	// p.prefix_parse_fns = make(100, 100, sizeof(PrefixParseFn))
	// p.prefix_parse_fns[token.Kind.name] = parse_name
	println('')
}

pub fn (p mut Parser) read_first_token() {
	// need to call next() twice to get peek token and current token
	p.next()
	p.next()
}

pub fn (p mut Parser) open_scope() {
	p.scope = &ast.Scope{
		parent: p.scope
		start_pos: p.tok.pos
	}
}

pub fn (p mut Parser) close_scope() {
	p.scope.end_pos = p.tok.pos
	p.scope.parent.children << p.scope
	p.scope = p.scope.parent
}

pub fn (p mut Parser) parse_block() []ast.Stmt {
	p.open_scope()
	// println('parse block')
	stmts := p.parse_block_no_scope()
	p.close_scope()
	// println('nr exprs in block = $exprs.len')
	return stmts
}

pub fn (p mut Parser) parse_block_no_scope() []ast.Stmt {
	p.check(.lcbr)
	mut stmts := []ast.Stmt
	if p.tok.kind != .rcbr {
		for {
			stmts << p.stmt()
			// p.warn('after stmt(): tok=$p.tok.str()')
			if p.tok.kind in [.eof, .rcbr] {
				break
			}
		}
	}
	p.check(.rcbr)
	return stmts
}

fn (p mut Parser) next() {
	// for {
	p.tok = p.peek_tok
	p.peek_tok = p.scanner.scan()
	// if !(p.tok.kind in [.line_comment, .mline_comment]) {
	// break
	// }
	// }
	// println(p.tok.str())
}

fn (p mut Parser) check(expected token.Kind) {
	// for p.tok.kind in [.line_comment, .mline_comment] {
	// p.next()
	// }
	if p.tok.kind != expected {
		s := 'syntax error: unexpected `${p.tok.kind.str()}`, expecting `${expected.str()}`'
		p.error(s)
	}
	p.next()
}

fn (p mut Parser) check_name() string {
	name := p.tok.lit
	p.check(.name)
	return name
}

pub fn (p mut Parser) top_stmt() ast.Stmt {
	match p.tok.kind {
		.key_pub {
			match p.peek_tok.kind {
				.key_const {
					return p.const_decl()
				}
				.key_fn {
					return p.fn_decl()
				}
				.key_struct, .key_union, .key_interface {
					return p.struct_decl()
				}
				.key_enum {
					return p.enum_decl()
				}
				.key_type {
					return p.type_decl()
				}
				else {
					p.error('wrong pub keyword usage')
					return ast.Stmt{}
				}
	}
		}
		.lsbr {
			return p.attribute()
		}
		.key_interface {
			return p.interface_decl()
		}
		.key_module {
			return p.module_decl()
		}
		.key_import {
			node := p.import_stmt()
			p.ast_imports << node
			return node[0]
		}
		.key_global {
			return p.global_decl()
		}
		.key_const {
			return p.const_decl()
		}
		.key_fn {
			return p.fn_decl()
		}
		.key_struct {
			return p.struct_decl()
		}
		.dollar {
			return p.comp_if()
		}
		.hash {
			return p.hash()
		}
		.key_type {
			return p.type_decl()
		}
		.key_enum {
			return p.enum_decl()
		}
		.key_union {
			return p.struct_decl()
		}
		.line_comment {
			return p.line_comment()
		}
		.mline_comment {
			comment := p.tok.lit
			p.next()
			return ast.MultiLineComment{
				text: comment
			}
		}
		else {
			// #printf("");
			p.error('parser: bad top level statement ' + p.tok.str())
			return ast.Stmt{}
		}
	}
}

pub fn (p mut Parser) line_comment() ast.LineComment {
	text := p.tok.lit
	p.next()
	return ast.LineComment{
		text: text
	}
}

pub fn (p mut Parser) stmt() ast.Stmt {
	match p.tok.kind {
		.lcbr {
			stmts := p.parse_block()
			return ast.Block{
				stmts: stmts
			}
		}
		.key_assert {
			p.next()
			expr := p.expr(0)
			return ast.AssertStmt{
				expr: expr
				pos: p.tok.position()
			}
		}
		.key_mut, .key_static {
			return p.assign_stmt()
		}
		.key_for {
			return p.for_statement()
		}
		.line_comment {
			return p.line_comment()
		}
		.key_return {
			return p.return_stmt()
		}
		.dollar {
			return p.comp_if()
		}
		.key_continue, .key_break {
			tok := p.tok
			p.next()
			return ast.BranchStmt{
				tok: tok
			}
		}
		.key_unsafe {
			p.next()
			stmts := p.parse_block()
			return ast.UnsafeStmt{
				stmts: stmts
			}
		}
		.hash {
			return p.hash()
		}
		.key_defer {
			p.next()
			stmts := p.parse_block()
			return ast.DeferStmt{
				stmts: stmts
			}
		}
		.key_go {
			p.next()
			return ast.GoStmt{
				expr: p.expr(0)
			}
		}
		.key_goto {
			p.next()
			name := p.check_name()
			return ast.GotoStmt{
				name: name
			}
		}
		else {
			// `x := ...`
			if p.tok.kind == .name && p.peek_tok.kind in [.decl_assign, .comma] {
				return p.assign_stmt()
			}
			// `label:`
			else if p.tok.kind == .name && p.peek_tok.kind == .colon {
				name := p.check_name()
				p.check(.colon)
				return ast.GotoLabel{
					name: name
				}
			}
			expr := p.expr(0)
			return ast.ExprStmt{
				expr: expr
			}
		}
	}
}

// TODO: is it possible to merge with AssignStmt?
pub fn (p mut Parser) assign_expr(left ast.Expr) ast.AssignExpr {
	op := p.tok.kind
	p.next()
	val := p.expr(0)
	node := ast.AssignExpr{
		left: left
		val: val
		op: op
		pos: p.tok.position()
	}
	return node
}

fn (p mut Parser) attribute() ast.Attr {
	p.check(.lsbr)
	if p.tok.kind == .key_if {
		p.next()
	}
	name := p.check_name()
	p.check(.rsbr)
	p.attr = name
	return ast.Attr{
		name: name
	}
}

/*
fn (p mut Parser) range_expr(low ast.Expr) ast.Expr {
	// ,table.Type) {
	if p.tok.kind != .dotdot {
		p.next()
	}
	p.check(.dotdot)
	mut high := ast.Expr{}
	if p.tok.kind != .rsbr {
		high = p.expr(0)
		// if typ.typ.kind != .int {
		// p.error('non-integer index `$typ.typ.name`')
		// }
	}
	node := ast.RangeExpr{
		low: low
		high: high
	}
	return node
}
*/


pub fn (p &Parser) error(s string) {
	print_backtrace()
	mut path := p.file_name
	// Get relative path
	workdir := os.getwd() + os.path_separator
	if path.starts_with(workdir) {
		path = path.replace(workdir, '')
	}
	final_msg_line := '$path:$p.tok.line_nr: error: $s'
	if colored_output {
		eprintln(term.bold(term.red(final_msg_line)))
	}
	else {
		eprintln(final_msg_line)
	}
	exit(1)
}

pub fn (p &Parser) error_at_line(s string, line_nr int) {
	final_msg_line := '$p.file_name:$line_nr: error: $s'
	if colored_output {
		eprintln(term.bold(term.red(final_msg_line)))
	}
	else {
		eprintln(final_msg_line)
	}
	exit(1)
}

pub fn (p &Parser) warn(s string) {
	final_msg_line := '$p.file_name:$p.tok.line_nr: warning: $s'
	if colored_output {
		eprintln(term.bold(term.blue(final_msg_line)))
	}
	else {
		eprintln(final_msg_line)
	}
}

pub fn (p mut Parser) parse_ident(is_c bool) ast.Ident {
	// p.warn('name ')
	pos := p.tok.position()
	mut name := p.check_name()
	if name == '_' {
		return ast.Ident{
			name: '_'
			kind: .blank_ident
			pos: pos
		}
	}
	if p.expr_mod.len > 0 {
		name = '${p.expr_mod}.$name'
	}
	mut ident := ast.Ident{
		kind: .unresolved
		name: name
		is_c: is_c
		pos: pos
	}
	// variable
	if p.expr_mod.len == 0 {
		if var := p.scope.find_var(name) {
			ident.kind = .variable
			ident.info = ast.IdentVar{}
		}
	}
	// handle consts/fns in checker
	return ident
}

fn (p mut Parser) struct_init() ast.StructInit {
	typ := p.parse_type()
	p.expr_mod = ''
	// sym := p.table.get_type_symbol(typ)
	// p.warn('struct init typ=$sym.name')
	p.check(.lcbr)
	mut field_names := []string
	mut exprs := []ast.Expr
	mut i := 0
	is_short_syntax := !(p.peek_tok.kind == .colon || p.tok.kind == .rcbr) // `Vec{a,b,c}`
	// p.warn(is_short_syntax.str())
	for p.tok.kind != .rcbr {
		mut field_name := ''
		if is_short_syntax {
			expr := p.expr(0)
			exprs << expr
		}
		else {
			field_name = p.check_name()
			field_names << field_name
		}
		if !is_short_syntax {
			p.check(.colon)
			expr := p.expr(0)
			exprs << expr
		}
		i++
		if p.tok.kind == .comma {
			p.check(.comma)
		}
	}
	node := ast.StructInit{
		typ: typ
		exprs: exprs
		fields: field_names
		pos: p.tok.position()
	}
	p.check(.rcbr)
	return node
}

pub fn (p mut Parser) name_expr() ast.Expr {
	mut node := ast.Expr{}
	is_c := p.tok.lit == 'C'
	mut mod := ''
	// p.warn('resetting')
	p.expr_mod = ''
	// `map[string]int` initialization
	if p.tok.lit == 'map' && p.peek_tok.kind == .lsbr {
		map_type := p.parse_map_type()
		return ast.MapInit{
			typ: map_type
		}
	}
	// Raw string (`s := r'hello \n ')
	if p.tok.lit in ['r', 'c'] && p.peek_tok.kind == .string {
		// QTODO
		// && p.prev_tok.kind != .str_dollar {
		return p.string_expr()
	}
	known_var := p.scope.known_var(p.tok.lit)
	if p.peek_tok.kind == .dot && !known_var && (is_c || p.known_import(p.tok.lit) || p.mod.all_after('.') == p.tok.lit) {
		if is_c {
			mod = 'C'
		}
		else {
			// prepend the full import
			mod = p.imports[p.tok.lit]
		}
		p.next()
		p.check(.dot)
		p.expr_mod = mod
	}
	// p.warn('name expr  $p.tok.lit $p.peek_tok.str()')
	// fn call or type cast
	if p.peek_tok.kind == .lpar {
		mut name := p.tok.lit
		if mod.len > 0 {
			name = '${mod}.$name'
		}
		name_w_mod := p.prepend_mod(name)
		// type cast. TODO: finish
		// if name in table.builtin_type_names {
		if (name in p.table.type_idxs || name_w_mod in p.table.type_idxs) && !(name in ['C.stat', 'C.sigaction']) {
			// TODO handle C.stat()
			mut to_typ := p.parse_type()
			if p.is_amp {
				// Handle `&Foo(0)`
				to_typ = table.type_to_ptr(to_typ)
			}
			p.check(.lpar)
			mut expr := ast.Expr{}
			mut arg := ast.Expr{}
			mut has_arg := false
			expr = p.expr(0)
			// TODO, string(b, len)
			if p.tok.kind == .comma && table.type_idx(to_typ) == table.string_type_idx {
				p.check(.comma)
				arg = p.expr(0) // len
				has_arg = true
			}
			p.check(.rpar)
			node = ast.CastExpr{
				typ: to_typ
				expr: expr
				arg: arg
				has_arg: has_arg
			}
			p.expr_mod = ''
			return node
		}
		// fn call
		else {
			// println('calling $p.tok.lit')
			x := p.call_expr(is_c, mod) // TODO `node,typ :=` should work
			node = x
		}
	}
	else if p.peek_tok.kind == .lcbr && (p.tok.lit[0].is_capital() || is_c ||
	//
	(p.builtin_mod && p.tok.lit in table.builtin_type_names)) &&
	//
	(p.tok.lit.len == 1 || !p.tok.lit[p.tok.lit.len - 1].is_capital())
	//
	{
		// || p.table.known_type(p.tok.lit)) {
		return p.struct_init()
	}
	else if p.peek_tok.kind == .dot && (p.tok.lit[0].is_capital() && !known_var) {
		// `Color.green`
		mut enum_name := p.check_name()
		if mod != '' {
			enum_name = mod + '.' + enum_name
		}
		else {
			enum_name = p.prepend_mod(enum_name)
		}
		// p.warn('Color.green $enum_name ' + p.prepend_mod(enum_name) + 'mod=$mod')
		p.check(.dot)
		val := p.check_name()
		// println('enum val $enum_name . $val')
		p.expr_mod = ''
		return ast.EnumVal{
			enum_name: enum_name // lp.prepend_mod(enum_name)
			
			val: val
			pos: p.tok.position()
			mod: mod
		}
	}
	else {
		mut ident := ast.Ident{}
		ident = p.parse_ident(is_c)
		node = ident
	}
	p.expr_mod = ''
	return node
}

pub fn (p mut Parser) expr(precedence int) ast.Expr {
	// println('\n\nparser.expr()')
	mut typ := table.void_type
	mut node := ast.Expr{}
	// Prefix
	match p.tok.kind {
		.name {
			node = p.name_expr()
		}
		.string {
			node = p.string_expr()
		}
		.dot {
			// .enum_val
			node = p.enum_val()
		}
		.chartoken {
			node = ast.CharLiteral{
				val: p.tok.lit
			}
			p.next()
		}
		// -1, -a, !x, &x, ~x
		.minus, .amp, .mul, .not, .bit_not {
			node = p.prefix_expr()
		}
		// .amp {
		// p.next()
		// }
		.key_true, .key_false {
			node = ast.BoolLiteral{
				val: p.tok.kind == .key_true
			}
			p.next()
		}
		.key_match {
			node = p.match_expr()
		}
		.number {
			node = p.parse_number_literal()
		}
		.lpar {
			p.check(.lpar)
			node = p.expr(0)
			p.check(.rpar)
			node = ast.ParExpr{
				expr: node
			}
		}
		.key_if {
			node = p.if_expr()
		}
		.lsbr {
			node = p.array_init()
		}
		.key_none {
			p.next()
			node = ast.None{}
		}
		.key_sizeof {
			p.next() // sizeof
			p.check(.lpar)
			if p.tok.lit == 'C' {
				p.next()
				p.check(.dot)
			}
			if p.tok.kind == .amp {
				p.next()
			}
			// type_name := p.check_name()
			sizeof_type := p.parse_type()
			p.check(.rpar)
			node = ast.SizeOf{
				typ: sizeof_type
				// type_name: type_name
				
			}
		}
		.key_typeof {
			p.next()
			p.check(.lpar)
			expr := p.expr(0)
			p.check(.rpar)
			node = ast.TypeOf{
				expr: expr
			}
		}
		// Map `{"age": 20}` or `{ x | foo:bar, a:10 }`
		.lcbr {
			p.next()
			if p.tok.kind == .string {
				mut keys := []ast.Expr
				mut vals := []ast.Expr
				for p.tok.kind != .rcbr && p.tok.kind != .eof {
					// p.check(.str)
					key := p.expr(0)
					keys << key
					p.check(.colon)
					val := p.expr(0)
					vals << val
					if p.tok.kind == .comma {
						p.next()
					}
				}
				node = ast.MapInit{
					keys: keys
					vals: vals
					pos: p.tok.position()
				}
			}
			else {
				name := p.check_name()
				var := p.scope.find_var(name) or {
					p.error('unknown variable `$name`')
					return node
				}
				// println('assoc var $name typ=$var.typ')
				mut fields := []string
				mut vals := []ast.Expr
				p.check(.pipe)
				for {
					fields << p.check_name()
					p.check(.colon)
					expr := p.expr(0)
					vals << expr
					if p.tok.kind == .comma {
						p.check(.comma)
					}
					if p.tok.kind == .rcbr {
						break
					}
				}
				node = ast.Assoc{
					var_name: name
					fields: fields
					exprs: vals
					pos: p.tok.position()
					typ: var.typ
				}
			}
			p.check(.rcbr)
		}
		else {
			p.error('parser: expr(): bad token `$p.tok.str()`')
		}
	}
	// Infix
	for precedence < p.tok.precedence() {
		if p.tok.kind.is_assign() {
			node = p.assign_expr(node)
		}
		else if p.tok.kind == .dot {
			node = p.dot_expr(node)
		}
		else if p.tok.kind == .lsbr {
			node = p.index_expr(node)
		}
		else if p.tok.kind == .key_as {
			pos := p.tok.position()
			p.next()
			typ = p.parse_type()
			node = ast.AsCast{
				expr: node
				typ: typ
				pos: pos
			}
		}
		// TODO: handle in later stages since this
		// will fudge left shift as it makes it right assoc
		// `arr << 'a'` | `arr << 'a' + 'b'`
		else if p.tok.kind == .left_shift {
			tok := p.tok
			p.next()
			right := p.expr(precedence - 1)
			node = ast.InfixExpr{
				left: node
				right: right
				op: tok.kind
				pos: tok.position()
			}
		}
		else if p.tok.kind.is_infix() {
			node = p.infix_expr(node)
		}
		// Postfix
		else if p.tok.kind in [.inc, .dec] {
			node = ast.PostfixExpr{
				op: p.tok.kind
				expr: node
				pos: p.tok.position()
			}
			p.next()
			// return node // TODO bring back, only allow ++/-- in exprs in translated code
		}
		else {
			return node
		}
	}
	return node
}

fn (p mut Parser) prefix_expr() ast.PrefixExpr {
	pos := p.tok.position()
	op := p.tok.kind
	if op == .amp {
		p.is_amp = true
	}
	p.next()
	right := p.expr(1)
	p.is_amp = false
	return ast.PrefixExpr{
		op: op
		right: right
		pos: pos
	}
}

fn (p mut Parser) index_expr(left ast.Expr) ast.IndexExpr {
	// left == `a` in `a[0]`
	p.next() // [
	mut has_low := true
	if p.tok.kind == .dotdot {
		has_low = false
		// [..end]
		p.next()
		high := p.expr(0)
		p.check(.rsbr)
		return ast.IndexExpr{
			left: left
			pos: p.tok.position()
			index: ast.RangeExpr{
				low: ast.Expr{}
				high: high
				has_high: true
			}
		}
	}
	expr := p.expr(0) // `[expr]` or  `[expr..]`
	mut has_high := false
	if p.tok.kind == .dotdot {
		// [start..end] or [start..]
		p.check(.dotdot)
		mut high := ast.Expr{}
		if p.tok.kind != .rsbr {
			has_high = true
			high = p.expr(0)
		}
		p.check(.rsbr)
		return ast.IndexExpr{
			left: left
			pos: p.tok.position()
			index: ast.RangeExpr{
				low: expr
				high: high
				has_high: has_high
				has_low: has_low
			}
		}
	}
	// [expr]
	p.check(.rsbr)
	return ast.IndexExpr{
		left: left
		index: expr
		pos: p.tok.position()
	}
}

fn (p mut Parser) filter() {
	p.scope.register_var(ast.Var{
		name: 'it'
	})
}

fn (p mut Parser) dot_expr(left ast.Expr) ast.Expr {
	p.next()
	field_name := p.check_name()
	is_filter := field_name in ['filter', 'map']
	if is_filter {
		p.open_scope()
		p.filter()
		// wrong tok position when using defer
		// defer {
		// p.close_scope()
		// }
	}
	pos := p.tok.position()
	// Method call
	if p.tok.kind == .lpar {
		p.next()
		args := p.call_args()
		mut or_stmts := []ast.Stmt
		if p.tok.kind == .key_orelse {
			p.next()
			p.open_scope()
			p.scope.register_var(ast.Var{
				name: 'err'
				typ: table.string_type
			})
			or_stmts = p.parse_block_no_scope()
			p.close_scope()
		}
		mcall_expr := ast.CallExpr{
			left: left
			name: field_name
			args: args
			pos: pos
			is_method: true
			or_block: ast.OrExpr{
				stmts: or_stmts
			}
		}
		mut node := ast.Expr{}
		node = mcall_expr
		if is_filter {
			p.close_scope()
		}
		return node
	}
	sel_expr := ast.SelectorExpr{
		expr: left
		field: field_name
		pos: p.tok.position()
	}
	mut node := ast.Expr{}
	node = sel_expr
	if is_filter {
		p.close_scope()
	}
	return node
}

fn (p mut Parser) infix_expr(left ast.Expr) ast.Expr {
	op := p.tok.kind
	// mut typ := p.
	// println('infix op=$op.str()')
	precedence := p.tok.precedence()
	pos := p.tok.position()
	p.next()
	mut right := ast.Expr{}
	right = p.expr(precedence)
	mut expr := ast.Expr{}
	expr = ast.InfixExpr{
		left: left
		right: right
		// right_type: typ
		
		op: op
		pos: pos
	}
	return expr
}

// Implementation of Pratt Precedence
/*
[inline]
fn (p &Parser) is_addative() bool {
	return p.tok.kind in [.plus, .minus] && p.peek_tok.kind in [.number, .name]
}
*/
// `.green`
// `pref.BuildMode.default_mode`
fn (p mut Parser) enum_val() ast.EnumVal {
	p.check(.dot)
	val := p.check_name()
	return ast.EnumVal{
		val: val
		pos: p.tok.position()
	}
}

fn (p mut Parser) for_statement() ast.Stmt {
	p.check(.key_for)
	pos := p.tok.position()
	p.open_scope()
	// defer { p.close_scope() }
	// Infinite loop
	if p.tok.kind == .lcbr {
		stmts := p.parse_block()
		p.close_scope()
		return ast.ForStmt{
			stmts: stmts
			pos: pos
			is_inf: true
		}
	}
	else if p.tok.kind == .key_mut {
		p.error('`mut` is not required in for loops')
	}
	// for i := 0; i < 10; i++ {
	else if p.peek_tok.kind in [.decl_assign, .assign, .semicolon] || p.tok.kind == .semicolon {
		mut init := ast.Stmt{}
		mut cond := p.new_true_expr()
		// mut inc := ast.Stmt{}
		mut inc := ast.Expr{}
		mut has_init := false
		if p.peek_tok.kind in [.assign, .decl_assign] {
			init = p.assign_stmt()
			has_init = true
		}
		else if p.tok.kind != .semicolon {}
		// allow `for ;; i++ {`
		// Allow `for i = 0; i < ...`
		/*
			cond, typ = p.expr(0)
			if typ.kind != _bool {
				p.error('non-bool used as for condition')
			}
			*/
		// println(1)
		// }
		p.check(.semicolon)
		if p.tok.kind != .semicolon {
			mut typ := table.void_type
			cond = p.expr(0)
		}
		p.check(.semicolon)
		if p.tok.kind != .lcbr {
			// inc = p.stmt()
			inc = p.expr(0)
		}
		stmts := p.parse_block()
		p.close_scope()
		return ast.ForCStmt{
			stmts: stmts
			has_init: has_init
			init: init
			cond: cond
			inc: inc
			pos: pos
		}
	}
	// `for i in vals`, `for i in start .. end`
	else if p.peek_tok.kind in [.key_in, .comma] {
		mut key_var_name := ''
		mut val_var_name := p.check_name()
		if p.tok.kind == .comma {
			p.check(.comma)
			key_var_name = val_var_name
			val_var_name = p.check_name()
			p.scope.register_var(ast.Var{
				name: key_var_name
				typ: table.int_type
			})
		}
		p.check(.key_in)
		// arr_expr
		cond := p.expr(0)
		// 0 .. 10
		// start := p.tok.lit.int()
		// TODO use RangeExpr
		mut high_expr := ast.Expr{}
		mut is_range := false
		if p.tok.kind == .dotdot {
			is_range = true
			p.check(.dotdot)
			high_expr = p.expr(0)
			p.scope.register_var(ast.Var{
				name: val_var_name
				typ: table.int_type
			})
		}
		else {
			// this type will be set in checker
			p.scope.register_var(ast.Var{
				name: val_var_name
			})
		}
		stmts := p.parse_block()
		// println('nr stmts=$stmts.len')
		p.close_scope()
		return ast.ForInStmt{
			stmts: stmts
			cond: cond
			key_var: key_var_name
			val_var: val_var_name
			high: high_expr
			is_range: is_range
			pos: pos
		}
	}
	// `for cond {`
	cond := p.expr(0)
	stmts := p.parse_block()
	p.close_scope()
	return ast.ForStmt{
		cond: cond
		stmts: stmts
		pos: pos
	}
}

fn (p mut Parser) if_expr() ast.IfExpr {
	p.inside_if = true
	pos := p.tok.position()
	mut branches := []ast.IfBranch
	mut has_else := false
	for p.tok.kind in [.key_if, .key_else] {
		branch_pos := p.tok.position()
		if p.tok.kind == .key_if {
			p.check(.key_if)
		}
		else {
			p.check(.key_else)
			if p.tok.kind == .key_if {
				p.check(.key_if)
			}
			else {
				has_else = true
				branches << ast.IfBranch{
					stmts: p.parse_block()
					pos: branch_pos
				}
				break
			}
		}
		mut cond := ast.Expr{}
		mut is_or := false
		// `if x := opt() {`
		if p.peek_tok.kind == .decl_assign {
			is_or = true
			p.open_scope()
			var_name := p.check_name()
			p.check(.decl_assign)
			expr := p.expr(0)
			p.scope.register_var(ast.Var{
				name: var_name
				expr: expr
			})
			cond = ast.IfGuardExpr{
				var_name: var_name
				expr: expr
			}
		}
		else {
			cond = p.expr(0)
		}
		p.inside_if = false
		stmts := p.parse_block()
		if is_or {
			p.close_scope()
		}
		branches << ast.IfBranch{
			cond: cond
			stmts: stmts
			pos: branch_pos
		}
		if p.tok.kind != .key_else {
			break
		}
	}
	return ast.IfExpr{
		branches: branches
		pos: pos
		has_else: has_else
	}
}

fn (p mut Parser) string_expr() ast.Expr {
	is_raw := p.tok.kind == .name && p.tok.lit == 'r'
	is_cstr := p.tok.kind == .name && p.tok.lit == 'c'
	if is_raw || is_cstr {
		p.next()
	}
	mut node := ast.Expr{}
	val := p.tok.lit
	node = ast.StringLiteral{
		val: val
		is_raw: is_raw
		is_c: is_cstr
	}
	if p.peek_tok.kind != .str_dollar {
		p.next()
		return node
	}
	mut exprs := []ast.Expr
	mut vals := []string
	mut efmts := []string
	// Handle $ interpolation
	for p.tok.kind == .string {
		vals << p.tok.lit
		p.next()
		if p.tok.kind != .str_dollar {
			continue
		}
		p.check(.str_dollar)
		exprs << p.expr(0)
		mut efmt := []string
		if p.tok.kind == .colon {
			efmt << ':'
			p.next()
		}
		// ${num:-2d}
		if p.tok.kind == .minus {
			efmt << '-'
			p.next()
		}
		// ${num:2d}
		if p.tok.kind == .number {
			efmt << p.tok.lit
			p.next()
			if p.tok.lit.len == 1 {
				efmt << p.tok.lit
				p.next()
			}
		}
		efmts << efmt.join('')
	}
	node = ast.StringInterLiteral{
		vals: vals
		exprs: exprs
		expr_fmts: efmts
	}
	return node
}

fn (p mut Parser) array_init() ast.ArrayInit {
	p.check(.lsbr)
	// p.warn('array_init() exp=$p.expected_type')
	mut array_type := table.void_type
	mut elem_type := table.void_type
	mut exprs := []ast.Expr
	if p.tok.kind == .rsbr {
		// []typ => `[]` and `typ` must be on the same line
		line_nr := p.tok.line_nr
		p.check(.rsbr)
		// []string
		if p.tok.kind in [.name, .amp] && p.tok.line_nr == line_nr {
			elem_type = p.parse_type()
			// this is set here becasue its a known type, others could be the
			// result of expr so we do those in checker
			idx := p.table.find_or_register_array(elem_type, 1)
			array_type = table.new_type(idx)
		}
	}
	else {
		// [1,2,3]
		for i := 0; p.tok.kind != .rsbr; i++ {
			expr := p.expr(0)
			exprs << expr
			if p.tok.kind == .comma {
				p.check(.comma)
			}
		}
		line_nr := p.tok.line_nr
		p.check(.rsbr)
		// [100]byte
		if exprs.len == 1 && p.tok.kind in [.name, .amp] && p.tok.line_nr == line_nr {
			elem_type = p.parse_type()
			// p.warn('fixed size array')
		}
	}
	// !
	if p.tok.kind == .not {
		p.next()
	}
	if p.tok.kind == .not {
		p.next()
	}
	return ast.ArrayInit{
		elem_type: elem_type
		typ: array_type
		exprs: exprs
		pos: p.tok.position()
	}
}

fn (p mut Parser) parse_number_literal() ast.Expr {
	lit := p.tok.lit
	mut node := ast.Expr{}
	if lit.contains('.') {
		node = ast.FloatLiteral{
			// val: lit.f64()
			val: lit
		}
	}
	else {
		node = ast.IntegerLiteral{
			val: lit
		}
	}
	p.next()
	return node
}

fn (p mut Parser) module_decl() ast.Module {
	p.check(.key_module)
	mod := p.check_name()
	full_mod := p.table.qualify_module(mod, p.file_name)
	p.mod = full_mod
	return ast.Module{
		name: full_mod
	}
}

fn (p mut Parser) parse_import() ast.Import {
	pos := p.tok.position()
	mut mod_name := p.check_name()
	mut mod_alias := mod_name
	for p.tok.kind == .dot {
		p.check(.dot)
		submod_name := p.check_name()
		mod_name += '.' + submod_name
		mod_alias = submod_name
	}
	if p.tok.kind == .key_as {
		p.check(.key_as)
		mod_alias = p.check_name()
	}
	p.imports[mod_alias] = mod_name
	p.table.imports << mod_name
	return ast.Import{
		mod: mod_name
		alias: mod_alias
		pos: pos
	}
}

fn (p mut Parser) import_stmt() []ast.Import {
	p.check(.key_import)
	mut imports := []ast.Import
	if p.tok.kind == .lpar {
		p.check(.lpar)
		for p.tok.kind != .rpar {
			imports << p.parse_import()
		}
		p.check(.rpar)
	}
	else {
		imports << p.parse_import()
	}
	return imports
}

fn (p mut Parser) const_decl() ast.ConstDecl {
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	p.check(.key_const)
	p.check(.lpar)
	mut fields := []ast.Field
	mut exprs := []ast.Expr
	for p.tok.kind != .rpar {
		name := p.prepend_mod(p.check_name())
		// println('!!const: $name')
		p.check(.assign)
		expr := p.expr(0)
		fields << ast.Field{
			name: name
			// typ: typ
			
		}
		exprs << expr
		// TODO: once consts are fixed reg here & update in checker
		// p.table.register_const(table.Var{
		// name: name
		// // typ: typ
		// })
	}
	p.check(.rpar)
	return ast.ConstDecl{
		fields: fields
		exprs: exprs
		is_pub: is_pub
	}
}

// structs and unions
fn (p mut Parser) struct_decl() ast.StructDecl {
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	if p.tok.kind == .key_struct {
		p.check(.key_struct)
	}
	else {
		p.check(.key_union)
	}
	is_c := p.tok.lit == 'C' && p.peek_tok.kind == .dot
	if is_c {
		p.next() // C
		p.next() // .
	}
	mut name := p.check_name()
	mut default_exprs := []ast.Expr
	// println('struct decl $name')
	p.check(.lcbr)
	mut ast_fields := []ast.Field
	mut fields := []table.Field
	mut mut_pos := -1
	mut pub_pos := -1
	mut pub_mut_pos := -1
	for p.tok.kind != .rcbr {
		if p.tok.kind == .key_pub {
			p.check(.key_pub)
			if p.tok.kind == .key_mut {
				p.check(.key_mut)
				pub_mut_pos = fields.len
			}
			else {
				pub_pos = fields.len
			}
			p.check(.colon)
		}
		else if p.tok.kind == .key_mut {
			p.check(.key_mut)
			p.check(.colon)
			mut_pos = fields.len
		}
		else if p.tok.kind == .key_global {
			p.check(.key_global)
			p.check(.colon)
		}
		field_name := p.check_name()
		// p.warn('field $field_name')
		typ := p.parse_type()
		/*
		if name == '_net_module_s' {
			s := p.table.get_type_symbol(typ)
			println('XXXX' + s.str())
		}
		*/

		// Default value
		if p.tok.kind == .assign {
			p.next()
			default_exprs << p.expr(0)
		}
		ast_fields << ast.Field{
			name: field_name
			typ: typ
		}
		fields << table.Field{
			name: field_name
			typ: typ
		}
		// println('struct field $ti.name $field_name')
	}
	p.check(.rcbr)
	if is_c {
		name = 'C.$name'
	}
	else {
		name = p.prepend_mod(name)
	}
	t := table.TypeSymbol{
		kind: .struct_
		name: name
		info: table.Struct{
			fields: fields
		}
	}
	mut ret := 0
	if p.builtin_mod && t.name in table.builtin_type_names {
		// this allows overiding the builtins type
		// with the real struct type info parsed from builtin
		ret = p.table.register_builtin_type_symbol(t)
	}
	else {
		ret = p.table.register_type_symbol(t)
	}
	if ret == -1 {
		p.error('cannot register type `$name`, another type with this name exists')
	}
	p.expr_mod = ''
	return ast.StructDecl{
		name: name
		is_pub: is_pub
		fields: ast_fields
		pos: p.tok.position()
		mut_pos: mut_pos
		pub_pos: pub_pos
		pub_mut_pos: pub_mut_pos
		is_c: is_c
		default_exprs: default_exprs
	}
}

fn (p mut Parser) interface_decl() ast.InterfaceDecl {
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	p.next() // `interface`
	interface_name := p.check_name()
	p.check(.lcbr)
	mut field_names := []string
	for p.tok.kind != .rcbr && p.tok.kind != .eof {
		line_nr := p.tok.line_nr
		name := p.check_name()
		field_names << name
		p.fn_args()
		if p.tok.kind == .name && p.tok.line_nr == line_nr {
			p.parse_type()
		}
	}
	p.check(.rcbr)
	return ast.InterfaceDecl{
		name: interface_name
		field_names: field_names
	}
}

fn (p mut Parser) return_stmt() ast.Return {
	p.next()
	// return expressions
	mut exprs := []ast.Expr
	if p.tok.kind == .rcbr {
		return ast.Return{
			pos: p.tok.position()
		}
	}
	for {
		expr := p.expr(0)
		exprs << expr
		if p.tok.kind == .comma {
			p.check(.comma)
		}
		else {
			break
		}
	}
	stmt := ast.Return{
		exprs: exprs
		pos: p.tok.position()
	}
	return stmt
}

// left hand side of `=` or `:=` in `a,b,c := 1,2,3`
fn (p mut Parser) parse_assign_lhs() []ast.Ident {
	mut idents := []ast.Ident
	for {
		is_mut := p.tok.kind == .key_mut
		if is_mut {
			p.check(.key_mut)
		}
		is_static := p.tok.kind == .key_static
		if is_static {
			p.check(.key_static)
		}
		mut ident := p.parse_ident(false)
		ident.info = ast.IdentVar{
			is_mut: is_mut
			is_static: is_static
		}
		idents << ident
		if p.tok.kind == .comma {
			p.check(.comma)
		}
		else {
			break
		}
	}
	return idents
}

// right hand side of `=` or `:=` in `a,b,c := 1,2,3`
fn (p mut Parser) parse_assign_rhs() []ast.Expr {
	mut exprs := []ast.Expr
	for {
		expr := p.expr(0)
		exprs << expr
		if p.tok.kind == .comma {
			p.check(.comma)
		}
		else {
			break
		}
	}
	return exprs
}

fn (p mut Parser) assign_stmt() ast.Stmt {
	is_static := p.tok.kind == .key_static
	if is_static {
		p.next()
	}
	idents := p.parse_assign_lhs()
	pos := p.tok.position()
	op := p.tok.kind
	p.next() // :=, =
	exprs := p.parse_assign_rhs()
	is_decl := op == .decl_assign
	for i, ident in idents {
		known_var := p.scope.known_var(ident.name)
		if !is_decl && !known_var {
			p.error('unknown variable `$ident.name`')
		}
		if is_decl && ident.kind != .blank_ident {
			if p.scope.known_var(ident.name) {
				p.error('redefinition of `$ident.name`')
			}
			if idents.len == exprs.len {
				p.scope.register_var(ast.Var{
					name: ident.name
					expr: exprs[i]
				})
			}
			else {
				p.scope.register_var(ast.Var{
					name: ident.name
				})
			}
		}
	}
	return ast.AssignStmt{
		left: idents
		right: exprs
		op: op
		pos: pos
		is_static: is_static
	}
}

fn (p mut Parser) hash() ast.HashStmt {
	val := p.tok.lit
	p.next()
	return ast.HashStmt{
		val: val
	}
}

fn (p mut Parser) global_decl() ast.GlobalDecl {
	if !p.pref.translated && !p.pref.is_live && !p.builtin_mod && !p.pref.building_v && p.mod != 'ui' && p.mod != 'gg2' && p.mod != 'uiold' && !os.getwd().contains('/volt') && !p.pref.enable_globals {
		p.error('use `v --enable-globals ...` to enable globals')
	}
	p.next()
	name := p.check_name()
	// println(name)
	typ := p.parse_type()
	if p.tok.kind == .assign {
		p.next()
		p.expr(0)
	}
	p.table.register_global(name, typ)
	// p.genln(p.table.cgen_name_type_pair(name, typ))
	/*
		mut g := p.table.cgen_name_type_pair(name, typ)
		if p.tok == .assign {
			p.next()
			g += ' = '
			_,expr := p.tmp_expr()
			g += expr
		}
		// p.genln('; // global')
		g += '; // global'
		if !p.cgen.nogen {
			p.cgen.consts << g
		}
		*/

	return ast.GlobalDecl{
		name: name
		typ: typ
	}
}

fn (p mut Parser) match_expr() ast.MatchExpr {
	p.check(.key_match)
	pos := p.tok.position()
	is_mut := p.tok.kind == .key_mut
	mut is_sum_type := false
	if is_mut {
		p.next()
	}
	cond := p.expr(0)
	p.check(.lcbr)
	mut branches := []ast.MatchBranch
	for {
		mut exprs := []ast.Expr
		branch_pos := p.tok.position()
		p.open_scope()
		// final else
		if p.tok.kind == .key_else {
			p.next()
		}
		// Sum type match
		else if p.tok.kind == .name && (p.tok.lit in table.builtin_type_names || p.tok.lit[0].is_capital() || p.peek_tok.kind == .dot) {
			// if sym.kind == .sum_type {
			// p.warn('is sum')
			// TODO `exprs << ast.Type{...}`
			typ := p.parse_type()
			x := ast.Type{
				typ: typ
			}
			mut expr := ast.Expr{}
			expr = x
			exprs << expr
			p.scope.register_var(ast.Var{
				name: 'it'
				typ: table.type_to_ptr(typ)
			})
			// TODO
			if p.tok.kind == .comma {
				p.next()
				p.parse_type()
			}
			is_sum_type = true
		}
		else {
			// Expression match
			for {
				expr := p.expr(0)
				exprs << expr
				if p.tok.kind != .comma {
					break
				}
				p.check(.comma)
			}
		}
		// p.warn('match block')
		stmts := p.parse_block()
		branches << ast.MatchBranch{
			exprs: exprs
			stmts: stmts
			pos: branch_pos
		}
		p.close_scope()
		if p.tok.kind == .rcbr {
			break
		}
	}
	p.check(.rcbr)
	return ast.MatchExpr{
		branches: branches
		cond: cond
		is_sum_type: is_sum_type
		pos: pos
	}
}

fn (p mut Parser) enum_decl() ast.EnumDecl {
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	p.check(.key_enum)
	name := p.prepend_mod(p.check_name())
	p.check(.lcbr)
	mut vals := []string
	mut default_exprs := []ast.Expr
	for p.tok.kind != .eof && p.tok.kind != .rcbr {
		val := p.check_name()
		vals << val
		// p.warn('enum val $val')
		if p.tok.kind == .assign {
			p.next()
			default_exprs << p.expr(0)
		}
		// Allow commas after enum, helpful for
		// enum Color {
		// r,g,b
		// }
		if p.tok.kind == .comma {
			p.next()
		}
	}
	p.check(.rcbr)
	p.table.register_type_symbol(table.TypeSymbol{
		kind: .enum_
		name: name
		info: table.Enum{
			vals: vals
		}
	})
	return ast.EnumDecl{
		name: name
		is_pub: is_pub
		vals: vals
		default_exprs: default_exprs
	}
}

fn (p mut Parser) type_decl() ast.TypeDecl {
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	p.check(.key_type)
	name := p.check_name()
	mut sum_variants := []table.Type
	if p.tok.kind == .assign {
		// type SumType = A | B | c
		p.next()
		for {
			variant_type := p.parse_type()
			sum_variants << variant_type
			if p.tok.kind != .pipe {
				break
			}
			p.check(.pipe)
		}
		p.table.register_type_symbol(table.TypeSymbol{
			kind: .sum_type
			name: p.prepend_mod(name)
			info: table.SumType{
				variants: sum_variants
			}
		})
		return ast.SumTypeDecl{
			name: name
			is_pub: is_pub
			sub_types: sum_variants
		}
	}
	// function type: `type mycallback fn(string, int)`
	if p.tok.kind == .key_fn {
		fn_name := p.prepend_mod(name)
		fn_type := p.parse_fn_type(fn_name)
		return ast.FnTypeDecl{
			name: fn_name
			is_pub: is_pub
			typ: fn_type
		}
	}
	// type MyType int
	parent_type := p.parse_type()
	pid := table.type_idx(parent_type)
	p.table.register_type_symbol(table.TypeSymbol{
		kind: .alias
		name: p.prepend_mod(name)
		parent_idx: pid
		info: table.Alias{
			foo: ''
		}
	})
	return ast.AliasTypeDecl{
		name: name
		is_pub: is_pub
		parent_type: parent_type
	}
}

fn (p &Parser) new_true_expr() ast.Expr {
	return ast.BoolLiteral{
		val: true
	}
}

fn verror(s string) {
	println(s)
	exit(1)
}
