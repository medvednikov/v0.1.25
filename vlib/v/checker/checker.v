// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module checker

import (
	v.ast
	v.table
	v.token
	os
)

const (
	max_nr_errors = 100
)

pub struct Checker {
	table          &table.Table
mut:
	file           ast.File
	nr_errors      int
	errors         []string
	expected_type  table.Type
	fn_return_type table.Type // current function's return type
	// fn_decl        ast.FnDecl
}

pub fn new_checker(table &table.Table) Checker {
	return Checker{
		table: table
	}
}

pub fn (c mut Checker) check(ast_file ast.File) {
	c.file = ast_file
	for stmt in ast_file.stmts {
		c.stmt(stmt)
	}
	/*
	println('all types:')
	for t in c.table.types {
		println(t.name + ' - ' + t.kind.str())
	}
	*/

}

pub fn (c mut Checker) check2(ast_file ast.File) []string {
	c.file = ast_file
	for stmt in ast_file.stmts {
		c.stmt(stmt)
	}
	return c.errors
}

pub fn (c mut Checker) check_files(ast_files []ast.File) {
	// TODO: temp fix, impl proper solution
	for file in ast_files {
		c.file = file
		for stmt in file.stmts {
			match mut stmt {
				ast.ConstDecl {
					c.stmt(*it)
				}
				else {}
	}
		}
	}
	for file in ast_files {
		c.check(file)
	}
}

pub fn (c mut Checker) struct_init(struct_init mut ast.StructInit) table.Type {
	// typ := c.table.find_type(struct_init.typ.typ.name) or {
	// c.error('unknown struct: $struct_init.typ.typ.name', struct_init.pos)
	// panic('')
	// }
	typ_sym := c.table.get_type_symbol(struct_init.typ)
	// println('check struct $typ_sym.name')
	match typ_sym.kind {
		.placeholder {
			c.error('unknown struct: $typ_sym.name', struct_init.pos)
		}
		// string & array are also structs but .kind of string/array
		.struct_, .string, .array {
			info := typ_sym.info as table.Struct
			is_short_syntax := struct_init.fields.len == 0
			if struct_init.exprs.len > info.fields.len {
				c.error('too many fields', struct_init.pos)
			}
			for i, expr in struct_init.exprs {
				// struct_field info.
				field_name := if is_short_syntax { info.fields[i].name } else { struct_init.fields[i] }
				mut field := info.fields[i]
				mut found_field := false
				for f in info.fields {
					if f.name == field_name {
						field = f
						found_field = true
						break
					}
				}
				if !found_field {
					c.error('struct init: no such field `$field_name` for struct `$typ_sym.name`', struct_init.pos)
				}
				c.expected_type = field.typ
				expr_type := c.expr(expr)
				expr_type_sym := c.table.get_type_symbol(expr_type)
				field_type_sym := c.table.get_type_symbol(field.typ)
				if !c.table.check(expr_type, field.typ) {
					c.error('cannot assign `$expr_type_sym.name` as `$field_type_sym.name` for field `$field.name`', struct_init.pos)
				}
				struct_init.expr_types << expr_type
				struct_init.expected_types << field.typ
			}
		}
		else {}
	}
	return struct_init.typ
}

pub fn (c mut Checker) infix_expr(infix_expr mut ast.InfixExpr) table.Type {
	// println('checker: infix expr(op $infix_expr.op.str())')
	left_type := c.expr(infix_expr.left)
	infix_expr.left_type = left_type
	c.expected_type = left_type
	right_type := c.expr(infix_expr.right)
	infix_expr.right_type = right_type
	right := c.table.get_type_symbol(right_type)
	if infix_expr.op == .key_in && !(right.kind in [.array, .map, .string]) {
		c.error('infix expr: `in` can only be used with array/map/string.', infix_expr.pos)
	}
	if !c.table.check(right_type, left_type) {
		left := c.table.get_type_symbol(left_type)
		// `array << elm`
		// the expressions have different types (array_x and x)
		if left.kind == .array && infix_expr.op == .left_shift {
			return table.void_type
		}
		// `elm in array`
		if right.kind in [.array, .map] && infix_expr.op == .key_in {
			return table.bool_type
		}
		c.error('infix expr: cannot use `$right.name` (right) as `$left.name`', infix_expr.pos)
	}
	if infix_expr.op.is_relational() {
		return table.bool_type
	}
	return left_type
}

fn (c mut Checker) assign_expr(assign_expr mut ast.AssignExpr) {
	left_type := c.expr(assign_expr.left)
	c.expected_type = left_type
	assign_expr.left_type = left_type
	// println('setting exp type to $c.expected_type $t.name')
	right_type := c.expr(assign_expr.val)
	assign_expr.right_type = right_type
	if ast.expr_is_blank_ident(assign_expr.left) {
		return
	}
	if !c.table.check(right_type, left_type) {
		left_type_sym := c.table.get_type_symbol(left_type)
		right_type_sym := c.table.get_type_symbol(right_type)
		c.error('cannot assign $right_type_sym.name to $left_type_sym.name', assign_expr.pos)
	}
}

pub fn (c mut Checker) call_expr(call_expr mut ast.CallExpr) table.Type {
	c.stmts(call_expr.or_block.stmts)
	if call_expr.is_method {
		left_type := c.expr(call_expr.left)
		call_expr.left_type = left_type
		left_type_sym := c.table.get_type_symbol(left_type)
		method_name := call_expr.name
		// TODO: remove this for actual methods, use only for compiler magic
		if left_type_sym.kind == .array && method_name in ['filter', 'clone', 'repeat', 'reverse', 'map', 'slice'] {
			if method_name in ['filter', 'map'] {
				array_info := left_type_sym.info as table.Array
				mut scope := c.file.scope.innermost(call_expr.pos.pos)
				scope.update_var_type('it', array_info.elem_type)
			}
			for i, arg in call_expr.args {
				c.expr(arg.expr)
			}
			// need to return `array_xxx` instead of `array`
			call_expr.return_type = left_type
			if method_name == 'clone' {
				// in ['clone', 'str'] {
				call_expr.receiver_type = table.type_to_ptr(left_type)
				// call_expr.return_type = call_expr.receiver_type
			}
			else {
				call_expr.receiver_type = left_type
			}
			return left_type
		}
		else if left_type_sym.kind == .array && method_name in ['first', 'last'] {
			info := left_type_sym.info as table.Array
			call_expr.return_type = info.elem_type
			call_expr.receiver_type = left_type
			return info.elem_type
		}
		if method := c.table.type_find_method(left_type_sym, method_name) {
			no_args := method.args.len - 1
			min_required_args := method.args.len - if method.is_variadic && method.args.len > 1 { 2 } else { 1 }
			if call_expr.args.len < min_required_args {
				c.error('too few arguments in call to `${left_type_sym.name}.$method_name` ($call_expr.args.len instead of $min_required_args)', call_expr.pos)
			}
			else if !method.is_variadic && call_expr.args.len > no_args {
				c.error('too many arguments in call to `${left_type_sym.name}.$method_name` ($call_expr.args.len instead of $no_args)', call_expr.pos)
				return method.return_type
			}
			// if method_name == 'clone' {
			// println('CLONE nr args=$method.args.len')
			// }
			// call_expr.args << method.args[0].typ
			// call_expr.exp_arg_types << method.args[0].typ
			for i, arg in call_expr.args {
				c.expected_type = if method.is_variadic && i >= method.args.len - 1 { method.args[method.args.len - 1].typ } else { method.args[i + 1].typ }
				call_expr.args[i].typ = c.expr(arg.expr)
			}
			// TODO: typ optimize.. this node can get processed more than once
			if call_expr.exp_arg_types.len == 0 {
				for i in 1 .. method.args.len {
					call_expr.exp_arg_types << method.args[i].typ
				}
			}
			call_expr.receiver_type = method.args[0].typ
			call_expr.return_type = method.return_type
			return method.return_type
		}
		// TODO: str methods
		if left_type_sym.kind == .map && method_name == 'str' {
			call_expr.receiver_type = table.new_type(c.table.type_idxs['map_string'])
			call_expr.return_type = table.string_type
			return table.string_type
		}
		if left_type_sym.kind == .array && method_name == 'str' {
			call_expr.receiver_type = left_type
			call_expr.return_type = table.string_type
			return table.string_type
		}
		c.error('unknown method: ${left_type_sym.name}.$method_name', call_expr.pos)
		return table.void_type
	}
	else {
		fn_name := call_expr.name
		// TODO: impl typeof properly (probably not going to be a fn call)
		if fn_name == 'typeof' {
			return table.string_type
		}
		// start hack: until v1 is fixed and c definitions are added for these
		if fn_name in ['C.calloc', 'C.malloc', 'C.exit', 'C.free'] {
			for arg in call_expr.args {
				c.expr(arg.expr)
			}
			if fn_name in ['C.calloc', 'C.malloc'] {
				return table.byteptr_type
			}
			return table.void_type
		}
		// end hack
		// look for function in format `mod.fn` or `fn` (main/builtin)
		mut f := table.Fn{}
		mut found := false
		// try prefix with current module as it would have never gotten prefixed
		if !fn_name.contains('.') && !(c.file.mod.name in ['builtin', 'main']) {
			name_prefixed := '${c.file.mod.name}.$fn_name'
			if f1 := c.table.find_fn(name_prefixed) {
				call_expr.name = name_prefixed
				found = true
				f = f1
			}
		}
		// already prefixed (mod.fn) or C/builtin/main
		if !found {
			if f1 := c.table.find_fn(fn_name) {
				found = true
				f = f1
			}
		}
		// check for arg (var) of fn type
		if !found {
			scope := c.file.scope.innermost(call_expr.pos.pos)
			if var := scope.find_var(fn_name) {
				if var.typ != 0 {
					vts := c.table.get_type_symbol(var.typ)
					if vts.kind == .function {
						info := vts.info as table.FnType
						f = info.func
						found = true
					}
				}
			}
		}
		if !found {
			c.error('unknown fn: $fn_name', call_expr.pos)
			return table.void_type
		}
		call_expr.return_type = f.return_type
		if f.is_c || call_expr.is_c {
			for arg in call_expr.args {
				c.expr(arg.expr)
			}
			return f.return_type
		}
		min_required_args := if f.is_variadic { f.args.len - 1 } else { f.args.len }
		if call_expr.args.len < min_required_args {
			c.error('too few arguments in call to `$fn_name` ($call_expr.args.len instead of $min_required_args)', call_expr.pos)
		}
		else if !f.is_variadic && call_expr.args.len > f.args.len {
			c.error('too many arguments in call to `$fn_name` ($call_expr.args.len instead of $f.args.len)', call_expr.pos)
			return f.return_type
		}
		// println can print anything
		if fn_name == 'println' {
			c.expected_type = table.string_type
			call_expr.args[0].typ = c.expr(call_expr.args[0].expr)
			return f.return_type
		}
		// TODO: typ optimize.. this node can get processed more than once
		if call_expr.exp_arg_types.len == 0 {
			for arg in f.args {
				call_expr.exp_arg_types << arg.typ
			}
		}
		for i, call_arg in call_expr.args {
			arg := if f.is_variadic && i >= f.args.len - 1 { f.args[f.args.len - 1] } else { f.args[i] }
			c.expected_type = arg.typ
			typ := c.expr(call_arg.expr)
			call_expr.args[i].typ = typ
			typ_sym := c.table.get_type_symbol(typ)
			arg_typ_sym := c.table.get_type_symbol(arg.typ)
			if !c.table.check(typ, arg.typ) {
				// str method, allow type with str method if fn arg is string
				if arg_typ_sym.kind == .string && typ_sym.has_method('str') {
					continue
				}
				// TODO const bug
				if typ_sym.kind == .void && arg_typ_sym.kind == .string {
					continue
				}
				if typ_sym.kind == .array_fixed {}
				// println('fixed')
				c.error('!cannot use type `$typ_sym.str()` as type `$arg_typ_sym.str()` in argument ${i+1} to `$fn_name`', call_expr.pos)
			}
		}
		return f.return_type
	}
}

pub fn (c mut Checker) selector_expr(selector_expr mut ast.SelectorExpr) table.Type {
	typ := c.expr(selector_expr.expr)
	if typ == table.void_type_idx {
		c.error('unknown selector expression', selector_expr.pos)
		return table.void_type
	}
	selector_expr.expr_type = typ
	// println('sel expr line_nr=$selector_expr.pos.line_nr typ=$selector_expr.expr_type')
	typ_sym := c.table.get_type_symbol(typ)
	field_name := selector_expr.field
	// variadic
	if table.type_is_variadic(typ) {
		if field_name == 'len' {
			return table.int_type
		}
	}
	if field := c.table.struct_find_field(typ_sym, field_name) {
		return field.typ
	}
	if typ_sym.kind != .struct_ {
		c.error('`$typ_sym.name` is not a struct', selector_expr.pos)
	}
	else {
		c.error('unknown field `${typ_sym.name}.$field_name`', selector_expr.pos)
	}
	return table.void_type
}

// TODO: non deferred
pub fn (c mut Checker) return_stmt(return_stmt mut ast.Return) {
	c.expected_type = c.fn_return_type
	if return_stmt.exprs.len == 0 {
		return
	}
	if return_stmt.exprs.len > 0 && c.fn_return_type == table.void_type {
		c.error('too many arguments to return, current function does not return anything', return_stmt.pos)
		return
	}
	expected_type := c.fn_return_type
	expected_type_sym := c.table.get_type_symbol(expected_type)
	exp_is_optional := table.type_is_optional(expected_type)
	mut expected_types := [expected_type]
	if expected_type_sym.kind == .multi_return {
		mr_info := expected_type_sym.info as table.MultiReturn
		expected_types = mr_info.types
	}
	mut got_types := []table.Type
	for expr in return_stmt.exprs {
		typ := c.expr(expr)
		got_types << typ
	}
	return_stmt.types = got_types
	// allow `none` & `error (Option)` return types for function that returns optional
	if exp_is_optional && table.type_idx(got_types[0]) in [table.none_type_idx, c.table.type_idxs['Option']] {
		return
	}
	if expected_types.len > 0 && expected_types.len != got_types.len {
		// c.error('wrong number of return arguments:\n\texpected: $expected_types.str()\n\tgot: $got_types.str()', return_stmt.pos)
		c.error('wrong number of return arguments', return_stmt.pos)
	}
	for i, exp_typ in expected_types {
		got_typ := got_types[i]
		if !c.table.check(got_typ, exp_typ) {
			got_typ_sym := c.table.get_type_symbol(got_typ)
			exp_typ_sym := c.table.get_type_symbol(exp_typ)
			c.error('cannot use `$got_typ_sym.name` as type `$exp_typ_sym.name` in return argument', return_stmt.pos)
		}
	}
}

pub fn (c mut Checker) assign_stmt(assign_stmt mut ast.AssignStmt) {
	c.expected_type = table.none_type // TODO a hack to make `x := if ... work`
	// multi return
	if assign_stmt.left.len > assign_stmt.right.len {
		match assign_stmt.right[0] {
			ast.CallExpr {}
			else {
				c.error('assign_stmt: expected call', assign_stmt.pos)
			}
	}
		right_type := c.expr(assign_stmt.right[0])
		right_type_sym := c.table.get_type_symbol(right_type)
		mr_info := right_type_sym.mr_info()
		if right_type_sym.kind != .multi_return {
			c.error('wrong number of vars', assign_stmt.pos)
		}
		mut scope := c.file.scope.innermost(assign_stmt.pos.pos)
		for i, _ in assign_stmt.left {
			mut ident := assign_stmt.left[i]
			mut ident_var_info := ident.var_info()
			val_type := mr_info.types[i]
			if assign_stmt.op == .assign {
				var_type := c.expr(ident)
				assign_stmt.left_types << var_type
				if !c.table.check(val_type, var_type) {
					val_type_sym := c.table.get_type_symbol(val_type)
					var_type_sym := c.table.get_type_symbol(var_type)
					c.error('assign stmt: cannot use `$val_type_sym.name` as `$var_type_sym.name`', assign_stmt.pos)
				}
			}
			ident_var_info.typ = val_type
			ident.info = ident_var_info
			assign_stmt.left[i] = ident
			assign_stmt.right_types << val_type
			scope.update_var_type(ident.name, val_type)
		}
	}
	// `a := 1` | `a,b := 1,2`
	else {
		if assign_stmt.left.len != assign_stmt.right.len {
			c.error('wrong number of vars', assign_stmt.pos)
		}
		mut scope := c.file.scope.innermost(assign_stmt.pos.pos)
		for i, _ in assign_stmt.left {
			mut ident := assign_stmt.left[i]
			mut ident_var_info := ident.var_info()
			val_type := c.expr(assign_stmt.right[i])
			if assign_stmt.op == .assign {
				var_type := c.expr(ident)
				assign_stmt.left_types << var_type
				if !c.table.check(val_type, var_type) {
					val_type_sym := c.table.get_type_symbol(val_type)
					var_type_sym := c.table.get_type_symbol(var_type)
					c.error('assign stmt: cannot use `$val_type_sym.name` as `$var_type_sym.name`', assign_stmt.pos)
				}
			}
			ident_var_info.typ = val_type
			ident.info = ident_var_info
			assign_stmt.left[i] = ident
			assign_stmt.right_types << val_type
			scope.update_var_type(ident.name, val_type)
		}
	}
	c.expected_type = table.void_type
}

pub fn (c mut Checker) array_init(array_init mut ast.ArrayInit) table.Type {
	// println('checker: array init $array_init.pos.line_nr $c.file.path')
	mut elem_type := table.void_type
	// []string - was set in parser
	if array_init.typ != table.void_type {
		return array_init.typ
	}
	// a = []
	if array_init.exprs.len == 0 {
		type_sym := c.table.get_type_symbol(c.expected_type)
		array_info := type_sym.array_info()
		array_init.elem_type = array_info.elem_type
		return c.expected_type
	}
	// [1,2,3]
	if array_init.exprs.len > 0 && array_init.elem_type == table.void_type {
		for i, expr in array_init.exprs {
			typ := c.expr(expr)
			// The first element's type
			if i == 0 {
				elem_type = typ
				c.expected_type = typ
				continue
			}
			if !c.table.check(elem_type, typ) {
				elem_type_sym := c.table.get_type_symbol(elem_type)
				c.error('expected array element with type `$elem_type_sym.name`', array_init.pos)
			}
		}
		idx := c.table.find_or_register_array(elem_type, 1)
		array_init.typ = table.new_type(idx)
		array_init.elem_type = elem_type
	}
	// [50]byte
	else if array_init.exprs.len == 1 && array_init.elem_type != table.void_type {
		mut fixed_size := 1
		match array_init.exprs[0] {
			ast.IntegerLiteral {
				fixed_size = it.val.int()
			}
			else {
				c.error('expecting `int` for fixed size', array_init.pos)
			}
	}
		idx := c.table.find_or_register_array_fixed(array_init.elem_type, fixed_size, 1)
		array_type := table.new_type(idx)
		array_init.typ = array_type
	}
	return array_init.typ
}

fn (c mut Checker) stmt(node ast.Stmt) {
	// c.expected_type = table.void_type
	match mut node {
		ast.AssertStmt {
			c.expr(it.expr)
		}
		ast.AssignStmt {
			c.assign_stmt(mut it)
		}
		ast.Block {
			c.stmts(it.stmts)
		}
		// ast.Attr {}
		ast.CompIf {
			// c.expr(it.cond)
			c.stmts(it.stmts)
			if it.has_else {
				c.stmts(it.else_stmts)
			}
		}
		ast.DeferStmt {
			c.stmts(it.stmts)
		}
		ast.ConstDecl {
			for i, expr in it.exprs {
				mut field := it.fields[i]
				typ := c.expr(expr)
				// TODO: once consts are fixed update here
				c.table.register_const(table.Var{
					name: field.name
					typ: typ
				})
				field.typ = typ
				it.fields[i] = field
			}
		}
		ast.ExprStmt {
			c.expr(it.expr)
			c.expected_type = table.void_type
		}
		ast.FnDecl {
			c.expected_type = table.void_type
			c.fn_return_type = it.return_type
			c.stmts(it.stmts)
		}
		ast.ForStmt {
			typ := c.expr(it.cond)
			if !it.is_inf && table.type_idx(typ) != table.bool_type_idx {
				c.error('non-bool used as for condition', it.pos)
			}
			// TODO: update loop var type
			// how does this work currenly?
			c.stmts(it.stmts)
		}
		ast.ForCStmt {
			c.stmt(it.init)
			c.expr(it.cond)
			// c.stmt(it.inc)
			c.expr(it.inc)
			c.stmts(it.stmts)
		}
		ast.ForInStmt {
			typ := c.expr(it.cond)
			if it.is_range {
				c.expr(it.high)
			}
			else {
				mut scope := c.file.scope.innermost(it.pos.pos)
				sym := c.table.get_type_symbol(typ)
				if it.key_var.len > 0 {
					key_type := match sym.kind {
						.map{
							sym.map_info().key_type
						}
						else {
							table.int_type}
	}
					it.key_type = key_type
					scope.update_var_type(it.key_var, key_type)
				}
				value_type := c.table.value_type(typ)
				if value_type == table.void_type {
					typ_sym := c.table.get_type_symbol(typ)
					c.error('for in: cannot index `$typ_sym.name`', it.pos)
				}
				it.cond_type = typ
				it.kind = sym.kind
				it.val_type = value_type
				scope.update_var_type(it.val_var, value_type)
			}
			c.stmts(it.stmts)
		}
		// ast.GlobalDecl {}
		// ast.HashStmt {}
		ast.Import {}
		ast.Return {
			c.return_stmt(mut it)
		}
		// ast.StructDecl {}
		ast.UnsafeStmt {
			c.stmts(it.stmts)
		}
		else {}
		// println('checker.stmt(): unhandled node')
		// println('checker.stmt(): unhandled node (${typeof(node)})')
		// }
	}
}

fn (c mut Checker) stmts(stmts []ast.Stmt) {
	c.expected_type = table.void_type
	for stmt in stmts {
		c.stmt(stmt)
	}
	c.expected_type = table.void_type
}

pub fn (c mut Checker) expr(node ast.Expr) table.Type {
	match mut node {
		ast.ArrayInit {
			return c.array_init(mut it)
		}
		ast.AsCast {
			it.expr_type = c.expr(it.expr)
			expr_type_sym := c.table.get_type_symbol(it.expr_type)
			type_sym := c.table.get_type_symbol(it.typ)
			if expr_type_sym.kind == .sum_type {
				info := expr_type_sym.info as table.SumType
				if !it.typ in info.variants {
					c.error('cannot cast `$expr_type_sym.name` to `$type_sym.name`', it.pos)
					// c.error('only $info.variants can be casted to `$typ`', it.pos)
				}
			}
			else {
				c.error('cannot cast non sum type `$type_sym.name` using `as`', it.pos)
			}
			return it.typ
		}
		ast.AssignExpr {
			c.assign_expr(mut it)
		}
		ast.Assoc {
			scope := c.file.scope.innermost(it.pos.pos)
			var := scope.find_var(it.var_name) or {
				panic(err)
			}
			for i, _ in it.fields {
				c.expr(it.exprs[i])
			}
			it.typ = var.typ
			return var.typ
		}
		ast.BoolLiteral {
			return table.bool_type
		}
		ast.CastExpr {
			it.expr_type = c.expr(it.expr)
			if it.has_arg {
				c.expr(it.arg)
			}
			return it.typ
		}
		ast.CallExpr {
			return c.call_expr(mut it)
		}
		ast.CharLiteral {
			return table.byte_type
		}
		ast.EnumVal {
			return c.enum_val(mut it)
		}
		ast.FloatLiteral {
			return table.f64_type
		}
		ast.Ident {
			return c.ident(mut it)
		}
		ast.IfExpr {
			return c.if_expr(mut it)
		}
		ast.IfGuardExpr {
			it.expr_type = c.expr(it.expr)
			return table.bool_type
		}
		ast.IndexExpr {
			return c.index_expr(mut it)
		}
		ast.InfixExpr {
			return c.infix_expr(mut it)
		}
		ast.IntegerLiteral {
			return table.int_type
		}
		ast.MapInit {
			return c.map_init(mut it)
		}
		ast.MatchExpr {
			return c.match_expr(mut it)
		}
		ast.PostfixExpr {
			return c.postfix_expr(it)
		}
		ast.PrefixExpr {
			right_type := c.expr(it.right)
			// TODO: testing ref/deref strategy
			if it.op == .amp && !table.type_is_ptr(right_type) {
				return table.type_to_ptr(right_type)
			}
			if it.op == .mul && table.type_is_ptr(right_type) {
				return table.type_deref(right_type)
			}
			if it.op == .not && right_type != table.bool_type_idx {
				c.error('! operator can only be used with bool types', it.pos)
			}
			return right_type
		}
		ast.None {
			return table.none_type
		}
		ast.ParExpr {
			return c.expr(it.expr)
		}
		ast.SelectorExpr {
			return c.selector_expr(mut it)
		}
		ast.SizeOf {
			return table.int_type
		}
		ast.StringLiteral {
			if it.is_c {
				return table.byteptr_type
			}
			return table.string_type
		}
		ast.StringInterLiteral {
			for expr in it.exprs {
				it.expr_types << c.expr(expr)
			}
			return table.string_type
		}
		ast.StructInit {
			return c.struct_init(mut it)
		}
		ast.Type {
			return it.typ
		}
		ast.TypeOf {
			it.expr_type = c.expr(it.expr)
			return table.string_type
		}
		else {}
		// println('checker.expr(): unhandled node')
		// TODO: find nil string bug triggered with typeof
		// println('checker.expr(): unhandled node (${typeof(node)})')
	}
	return table.void_type
}

pub fn (c mut Checker) ident(ident mut ast.Ident) table.Type {
	// println('IDENT: $ident.name - $ident.pos.pos')
	if ident.kind == .variable {
		// println('===========================')
		// c.scope.print_vars(0)
		// println('===========================')
		info := ident.info as ast.IdentVar
		if info.typ != 0 {
			return info.typ
		}
		start_scope := c.file.scope.innermost(ident.pos.pos)
		mut found := true
		mut var_scope,var := start_scope.find_scope_and_var(ident.name) or {
			found = false
			c.error('not found: $ident.name - POS: $ident.pos.pos', ident.pos)
			panic('')
		}
		if found {
			// update the variable
			// we need to do this here instead of var_decl since some
			// vars are registered manually for things like for loops etc
			// NOTE: or consider making those declarations part of those ast nodes
			mut typ := var.typ
			// set var type on first use
			if typ == 0 {
				typ = c.expr(var.expr)
				var_scope.update_var_type(var.name, typ)
			}
			// update ident
			ident.kind = .variable
			ident.info = ast.IdentVar{
				typ: typ
				is_optional: table.type_is_optional(typ)
			}
			// unwrap optional (`println(x)`)
			if table.type_is_optional(typ) {
				return table.type_clear_extra(typ)
			}
			return typ
		}
	}
	// second use, already resovled in unresolved branch
	else if ident.kind == .constant {
		info := ident.info as ast.IdentVar
		return info.typ
	}
	// second use, already resovled in unresovled branch
	else if ident.kind == .function {
		info := ident.info as ast.IdentFn
		return info.typ
	}
	// Handle indents with unresolved types during the parsing step
	// (declared after first usage)
	else if ident.kind == .unresolved {
		// prepend mod to look for fn call or const
		mut name := ident.name
		if !name.contains('.') && !(c.file.mod.name in ['builtin', 'main']) {
			name = '${c.file.mod.name}.$ident.name'
		}
		// hack - const until consts are fixed properly
		if ident.name == 'v_modules_path' {
			ident.name = name
			ident.kind = .constant
			ident.info = ast.IdentVar{
				typ: table.string_type
			}
			return table.string_type
		}
		// constant
		if constant := c.table.find_const(name) {
			ident.name = name
			ident.kind = .constant
			ident.info = ast.IdentVar{
				typ: constant.typ
			}
			return constant.typ
		}
		// Function object (not a call), e.g. `onclick(my_click)`
		if func := c.table.find_fn(name) {
			fn_type := table.new_type(c.table.find_or_register_fn_type(func, true))
			ident.name = name
			ident.kind = .function
			ident.info = ast.IdentFn{
				typ: fn_type
			}
			return fn_type
		}
	}
	// TODO
	// c.error('unknown ident: `$ident.name`', ident.pos)
	if ident.is_c {
		return table.int_type
	}
	return table.void_type
}

pub fn (c mut Checker) match_expr(node mut ast.MatchExpr) table.Type {
	node.is_expr = c.expected_type != table.void_type
	node.expected_type = c.expected_type
	cond_type := c.expr(node.cond)
	if cond_type == 0 {
		c.error('match 0 cond type', node.pos)
	}
	c.expected_type = cond_type
	mut ret_type := table.void_type
	for branch in node.branches {
		for expr in branch.exprs {
			c.expected_type = cond_type
			typ := c.expr(expr)
			typ_sym := c.table.get_type_symbol(typ)
			// TODO:
			if typ_sym.kind == .sum_type {}
		}
		c.stmts(branch.stmts)
		// If the last statement is an expression, return its type
		if branch.stmts.len > 0 {
			match branch.stmts[branch.stmts.len - 1] {
				ast.ExprStmt {
					ret_type = c.expr(it.expr)
				}
				// TODO: ask alex about this
				// typ := c.expr(it.expr)
				// type_sym := c.table.get_type_symbol(typ)
				// p.warn('match expr ret $type_sym.name')
				// node.typ = typ
				// return typ
				else {}
	}
		}
	}
	// if ret_type != table.void_type {
	// node.is_expr = c.expected_type != table.void_type
	// node.expected_type = c.expected_type
	// }
	node.return_type = ret_type
	node.cond_type = cond_type
	// println('!m $expr_type')
	return ret_type
}

pub fn (c mut Checker) if_expr(node mut ast.IfExpr) table.Type {
	if c.expected_type != table.void_type {
		// sym := c.table.get_type_symbol(c.expected_type)
		// println('$c.file.path  $node.pos.line_nr IF: checker exp type = ' + sym.name)
		node.is_expr = true
	}
	node.typ = table.void_type
	for i, branch in node.branches {
		match branch.cond {
			ast.ParExpr {
				c.error('unnecessary `()` in an if condition. use `if expr {` instead of `if (expr) {`.', node.pos)
			}
			else {}
	}
		typ := c.expr(branch.cond)
		if i < node.branches.len - 1 || !node.has_else {
			typ_sym := c.table.get_type_symbol(typ)
			// if typ_sym.kind != .bool {
			if table.type_idx(typ) != table.bool_type_idx {
				c.error('non-bool (`$typ_sym.name`) used as if condition', node.pos)
			}
		}
		c.stmts(branch.stmts)
	}
	if node.has_else && node.is_expr {
		last_branch := node.branches[node.branches.len - 1]
		if last_branch.stmts.len > 0 {
			match last_branch.stmts[last_branch.stmts.len - 1] {
				ast.ExprStmt {
					// type_sym := p.table.get_type_symbol(it.typ)
					// p.warn('if expr ret $type_sym.name')
					t := c.expr(it.expr)
					node.typ = t
					return t
				}
				else {}
	}
		}
	}
	return table.bool_type
}

pub fn (c mut Checker) postfix_expr(node ast.PostfixExpr) table.Type {
	/*
	match node.expr {
		ast.IdentVar {
			println('postfix identvar')
		}
		else {}
	}
	*/
	typ := c.expr(node.expr)
	typ_sym := c.table.get_type_symbol(typ)
	// if !table.is_number(typ) {
	if !typ_sym.is_number() {
		println(typ_sym.kind.str())
		c.error('invalid operation: $node.op.str() (non-numeric type `$typ_sym.name`)', node.pos)
	}
	return typ
}

pub fn (c mut Checker) index_expr(node mut ast.IndexExpr) table.Type {
	typ := c.expr(node.left)
	mut is_range := false // TODO is_range := node.index is ast.RangeExpr
	match node.index {
		ast.RangeExpr {
			is_range = true
			if it.has_low {
				c.expr(it.low)
			}
			if it.has_high {
				c.expr(it.high)
			}
		}
		else {}
	}
	node.container_type = typ
	typ_sym := c.table.get_type_symbol(typ)
	if !is_range {
		index_type := c.expr(node.index)
		index_type_sym := c.table.get_type_symbol(index_type)
		// println('index expr left=$typ_sym.name $node.pos.line_nr')
		// if typ_sym.kind == .array && (!(table.type_idx(index_type) in table.number_type_idxs) &&
		// index_type_sym.kind != .enum_) {
		if typ_sym.kind in [.array, .array_fixed] && !(table.is_number(index_type) || index_type_sym.kind == .enum_) {
			c.error('non-integer index `$index_type_sym.name` (array type `$typ_sym.name`)', node.pos)
		}
		else if typ_sym.kind == .map && table.type_idx(index_type) != table.string_type_idx {
			c.error('non-string map index (map type `$typ_sym.name`)', node.pos)
		}
		value_type := c.table.value_type(typ)
		if value_type != table.void_type {
			return value_type
		}
	}
	else if is_range {
		// array[1..2] => array
		// fixed_array[1..2] => array
		if typ_sym.kind == .array_fixed {
			elem_type := c.table.value_type(typ)
			idx := c.table.find_or_register_array(elem_type, 1)
			return table.new_type(idx)
		}
	}
	return typ
}

// `.green` or `Color.green`
// If a short form is used, `expected_type` needs to be an enum
// with this value.
pub fn (c mut Checker) enum_val(node mut ast.EnumVal) table.Type {
	typ_idx := if node.enum_name == '' { table.type_idx(c.expected_type) } else { //
	c.table.find_type_idx(node.enum_name) }
	// println('checker: enum_val: $node.enum_name typeidx=$typ_idx')
	if typ_idx == 0 {
		c.error('not an enum (name=$node.enum_name) (type_idx=0)', node.pos)
	}
	typ := table.new_type(typ_idx)
	typ_sym := c.table.get_type_symbol(typ)
	// println('tname=$typ.name')
	if typ_sym.kind != .enum_ {
		c.error('not an enum', node.pos)
	}
	// info := typ_sym.info as table.Enum
	info := typ_sym.enum_info()
	// rintln('checker: x = $info.x enum val $c.expected_type $typ_sym.name')
	// println(info.vals)
	if !(node.val in info.vals) {
		c.error('enum `$typ_sym.name` does not have a value `$node.val`', node.pos)
	}
	node.typ = typ
	return typ
}

pub fn (c mut Checker) map_init(node mut ast.MapInit) table.Type {
	// `x ;= map[string]string` - set in parser
	if node.typ != 0 {
		info := c.table.get_type_symbol(node.typ).map_info()
		node.key_type = info.key_type
		node.value_type = info.value_type
		return node.typ
	}
	// `{'age': 20}`
	key0_type := c.expr(node.keys[0])
	val0_type := c.expr(node.vals[0])
	for i, key in node.keys {
		if i == 0 {
			continue
		}
		val := node.vals[i]
		key_type := c.expr(key)
		val_type := c.expr(val)
		if !c.table.check(key_type, key0_type) {
			key0_type_sym := c.table.get_type_symbol(key0_type)
			key_type_sym := c.table.get_type_symbol(key_type)
			c.error('map init: cannot use `$key_type_sym.name` as `$key0_type_sym` for map key', node.pos)
		}
		if !c.table.check(val_type, val0_type) {
			val0_type_sym := c.table.get_type_symbol(val0_type)
			val_type_sym := c.table.get_type_symbol(val_type)
			c.error('map init: cannot use `$val_type_sym.name` as `$val0_type_sym` for map value', node.pos)
		}
	}
	map_type := table.new_type(c.table.find_or_register_map(key0_type, val0_type))
	node.typ = map_type
	node.key_type = key0_type
	node.value_type = val0_type
	return map_type
}

pub fn (c mut Checker) error(s string, pos token.Position) {
	c.nr_errors++
	print_backtrace()
	mut path := c.file.path
	// Get relative path
	workdir := os.getwd() + os.path_separator
	if path.starts_with(workdir) {
		path = path.replace(workdir, '')
	}
	final_msg_line := '$path:$pos.line_nr: checker error #$c.nr_errors: $s'
	c.errors << final_msg_line
	eprintln(final_msg_line)
	/*
	if colored_output {
		eprintln(term.bold(term.red(final_msg_line)))
	}else{
		eprintln(final_msg_line)
	}
	*/

	println('\n\n')
	if c.nr_errors >= max_nr_errors {
		exit(1)
	}
}
