// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module parser

import (
	v.ast
	v.table
)

pub fn (p mut Parser) call_expr(is_c bool, mod string) ast.CallExpr {
	tok := p.tok
	name := p.check_name()
	fn_name := if is_c { 'C.$name' } else if mod.len > 0 { '${mod}.$name' } else { name }
	p.check(.lpar)
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
	node := ast.CallExpr{
		name: fn_name
		args: args
		// tok: tok
		
		pos: tok.position()
		is_c: is_c
		or_block: ast.OrExpr{
			stmts: or_stmts
		}
	}
	return node
}

pub fn (p mut Parser) call_args() []ast.CallArg {
	mut args := []ast.CallArg
	for p.tok.kind != .rpar {
		mut is_mut := false
		if p.tok.kind == .key_mut {
			p.check(.key_mut)
			is_mut = true
		}
		e := p.expr(0)
		args << ast.CallArg{
			is_mut: is_mut
			expr: e
		}
		if p.tok.kind != .rpar {
			p.check(.comma)
		}
	}
	p.check(.rpar)
	return args
}

fn (p mut Parser) fn_decl() ast.FnDecl {
	// p.table.clear_vars()
	p.open_scope()
	is_deprecated := p.attr == 'deprecated'
	is_pub := p.tok.kind == .key_pub
	if is_pub {
		p.next()
	}
	p.check(.key_fn)
	// C.
	is_c := p.tok.kind == .name && p.tok.lit == 'C'
	if is_c {
		p.next()
		p.check(.dot)
	}
	// Receiver?
	mut rec_name := ''
	mut is_method := false
	mut rec_type := table.void_type
	mut rec_mut := false
	mut args := []table.Arg
	if p.tok.kind == .lpar {
		is_method = true
		p.next()
		rec_name = p.check_name()
		rec_mut = p.tok.kind == .key_mut
		// if rec_mut {
		// p.check(.key_mut)
		// }
		// TODO: talk to alex, should mut be parsed with the type like this?
		// or should it be a property of the arg, like this ptr/mut becomes indistinguishable
		rec_type = p.parse_type()
		args << table.Arg{
			name: rec_name
			is_mut: rec_mut
			typ: rec_type
		}
		p.check(.rpar)
	}
	mut name := ''
	if p.tok.kind == .name {
		// TODO high order fn
		name = p.check_name()
	}
	if p.tok.kind in [.plus, .minus, .mul, .div, .mod] {
		name = p.tok.kind.str() // op_to_fn_name()
		p.next()
	}
	// <T>
	if p.tok.kind == .lt {
		p.next()
		p.next()
		p.check(.gt)
	}
	// Args
	args2,is_variadic := p.fn_args()
	args << args2
	for arg in args {
		p.scope.register_var(ast.Var{
			name: arg.name
			typ: arg.typ
		})
	}
	// Return type
	mut return_type := table.void_type
	if p.tok.kind.is_start_of_type() {
		return_type = p.parse_type()
	}
	// Register
	if is_method {
		mut type_sym := p.table.get_type_symbol(rec_type)
		// p.warn('reg method $type_sym.name . $name ()')
		type_sym.register_method(table.Fn{
			name: name
			args: args
			return_type: return_type
			is_variadic: is_variadic
		})
	}
	else {
		if is_c {
			name = 'C.$name'
		}
		else {
			name = p.prepend_mod(name)
		}
		p.table.register_fn(table.Fn{
			name: name
			args: args
			return_type: return_type
			is_variadic: is_variadic
			is_c: is_c
		})
	}
	mut stmts := []ast.Stmt
	no_body := p.tok.kind != .lcbr
	if p.tok.kind == .lcbr {
		stmts = p.parse_block()
	}
	p.close_scope()
	p.attr = ''
	return ast.FnDecl{
		name: name
		stmts: stmts
		return_type: return_type
		args: args
		is_deprecated: is_deprecated
		is_pub: is_pub
		is_variadic: is_variadic
		receiver: ast.Field{
			name: rec_name
			typ: rec_type
		}
		is_method: is_method
		rec_mut: rec_mut
		is_c: is_c
		no_body: no_body
		pos: p.tok.position()
	}
}

fn (p mut Parser) fn_args() ([]table.Arg,bool) {
	p.check(.lpar)
	mut args := []table.Arg
	mut is_variadic := false
	// `int, int, string` (no names, just types)
	types_only := p.tok.kind in [.amp, .and] || (p.peek_tok.kind == .comma && p.table.known_type(p.tok.lit)) || p.peek_tok.kind == .rpar
	if types_only {
		// p.warn('types only')
		mut arg_no := 1
		for p.tok.kind != .rpar {
			arg_name := 'arg_$arg_no'
			is_mut := p.tok.kind == .key_mut
			if is_mut {
				p.check(.key_mut)
			}
			if p.tok.kind == .ellipsis {
				p.check(.ellipsis)
				is_variadic = true
			}
			mut arg_type := p.parse_type()
			if is_variadic {
				arg_type = table.type_to_variadic(arg_type)
			}
			if p.tok.kind == .comma {
				if is_variadic {
					p.error('cannot use ...(variadic) with non-final parameter no $arg_no')
				}
				p.next()
			}
			args << table.Arg{
				name: arg_name
				is_mut: is_mut
				typ: arg_type
			}
			arg_no++
		}
	}
	else {
		for p.tok.kind != .rpar {
			mut arg_names := [p.check_name()]
			// `a, b, c int`
			for p.tok.kind == .comma {
				p.check(.comma)
				arg_names << p.check_name()
			}
			is_mut := p.tok.kind == .key_mut
			// if is_mut {
			// p.check(.key_mut)
			// }
			if p.tok.kind == .ellipsis {
				p.check(.ellipsis)
				is_variadic = true
			}
			mut typ := p.parse_type()
			if is_variadic {
				typ = table.type_to_variadic(typ)
			}
			for arg_name in arg_names {
				args << table.Arg{
					name: arg_name
					is_mut: is_mut
					typ: typ
				}
				// if typ.typ.kind == .variadic && p.tok.kind == .comma {
				if is_variadic && p.tok.kind == .comma {
					p.error('cannot use ...(variadic) with non-final parameter $arg_name')
				}
			}
			if p.tok.kind != .rpar {
				p.check(.comma)
			}
		}
	}
	p.check(.rpar)
	return args,is_variadic
}

fn (p &Parser) fileis(s string) bool {
	return p.file_name.contains(s)
}
