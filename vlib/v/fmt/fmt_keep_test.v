import (
	os
	term
	benchmark
	v.fmt
	v.parser
	v.table
	v.pref
)

const (
	error_missing_vexe = 1
	error_failed_tests = 2
)

fn test_fmt() {
	fmt_message := 'checking that v fmt keeps already formatted files *unchanged*'
	eprintln(term.header(fmt_message, '-'))
	vexe := os.getenv('VEXE')
	if vexe.len == 0 || !os.exists(vexe) {
		eprintln('VEXE must be set')
		exit(error_missing_vexe)
	}
	vroot := os.dir(vexe)
	tmpfolder := os.temp_dir()
	diff_cmd := find_working_diff_command() or {
		''
	}
	mut fmt_bench := benchmark.new_benchmark()
	keep_input_files := os.walk_ext('$vroot/vlib/v/fmt/tests', '_keep.vv')
	expected_input_files := os.walk_ext('$vroot/vlib/v/fmt/tests', '_expected.vv')
	mut input_files := []string
	input_files << keep_input_files
	input_files << expected_input_files
	fmt_bench.set_total_expected_steps(input_files.len)
	for istep, ipath in input_files {
		fmt_bench.cstep = istep
		fmt_bench.step()
		ifilename := os.file_name(ipath)
		opath := ipath
		expected_ocontent := os.read_file(opath) or {
			fmt_bench.fail()
			eprintln(fmt_bench.step_message_fail('cannot read from ${opath}'))
			continue
		}
		table := table.new_table()
		file_ast := parser.parse_file(ipath, table, .parse_comments, &pref.Preferences{})
		result_ocontent := fmt.fmt(file_ast, table)
		if expected_ocontent != result_ocontent {
			fmt_bench.fail()
			eprintln(fmt_bench.step_message_fail('file ${ipath} after formatting, does not look as expected.'))
			if diff_cmd == '' {
				eprintln('>> sorry, but no working "diff" CLI command can be found')
				continue
			}
			vfmt_result_file := os.join_path(tmpfolder,'vfmt_run_over_${ifilename}')
			os.write_file(vfmt_result_file, result_ocontent)
			os.system('$diff_cmd --minimal  --text   --unified=2 --show-function-line="fn " "$opath" "$vfmt_result_file"')
			continue
		}
		fmt_bench.ok()
		eprintln(fmt_bench.step_message_ok('${ipath}'))
	}
	fmt_bench.stop()
	eprintln(term.h_divider('-'))
	eprintln(fmt_bench.total_message(fmt_message))
	if fmt_bench.nfail > 0 {
		exit(error_failed_tests)
	}
}

fn find_working_diff_command() ?string {
	for diffcmd in ['colordiff', 'diff', 'colordiff.exe', 'diff.exe'] {
		p := os.exec('$diffcmd --version') or {
			continue
		}
		if p.exit_code == 0 {
			return diffcmd
		}
	}
	return error('no working diff command found')
}
