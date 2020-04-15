// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module ast
/*
These methods are used only by vfmt, vdoc, and for debugging.
*/


import (
	v.table
	strings
)

pub fn (node &FnDecl) str(t &table.Table) string {
	mut f := strings.new_builder(30)
	if node.is_pub {
		f.write('pub ')
	}
	mut receiver := ''
	if node.is_method {
		sym := t.get_type_symbol(node.receiver.typ)
		name := sym.name.after('.')
		m := if node.rec_mut { 'mut ' } else { '' }
		receiver = '($node.receiver.name $m$name) '
	}
	name := node.name.after('.')
	f.write('fn ${receiver}${name}(')
	for i, arg in node.args {
		// skip receiver
		if node.is_method && i == 0 {
			continue
		}
		is_last_arg := i == node.args.len - 1
		should_add_type := is_last_arg || node.args[i + 1].typ != arg.typ ||
									(node.is_variadic && i == node.args.len - 2)
		f.write(arg.name)
		if should_add_type {
			if node.is_variadic && is_last_arg {
				f.write(' ...' + t.type_to_str(arg.typ))
			}
			else {
				f.write(' ' + t.type_to_str(arg.typ))
			}
		}
		if !is_last_arg {
			f.write(', ')
		}
	}
	f.write(')')
	if node.return_type != table.void_type {
		// typ := t.type_to_str(node.typ)
		// if typ.starts_with('
		f.write(' ' + t.type_to_str(node.return_type))
	}
	return f.str()
}

// string representaiton of expr
pub fn (x Expr) str() string {
	match x {
		Ident {
			return it.name
		}
		InfixExpr {
			return '(${it.left.str()} $it.op.str() ${it.right.str()})'
		}
		/*
		PrefixExpr {
			return it.left.str() + it.op.str()
		}
		*/

		IntegerLiteral {
			return it.val
		}
		StringLiteral {
			return '"$it.val"'
		}
		else {
			return ''
		}
	}
}

pub fn (node Stmt) str() string {
	match node {
		AssignStmt {
			mut out := ''
			for i,ident in it.left {
				var_info := ident.var_info()
				if var_info.is_mut {
					out += 'mut '
				}
				out += ident.name
				if i < it.left.len-1 {
					out += ','
				}
			}
			out += ' $it.op.str() '
			for i,val in it.right {
				out += val.str()
				if i < it.right.len-1 {
					out += ','
				}
			}
			return out
		}
		ExprStmt {
			return it.expr.str()
		}
		FnDecl {
			return 'fn ${it.name}() { $it.stmts.len stmts }'
		}
		else {
			return '[unhandled stmt str]'
		}
	}
}
