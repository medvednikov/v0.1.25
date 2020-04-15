import os
import term
import benchmark

fn test_all() {
	$if tinyc {
		eprintln('Temporarily disabled for tcc, till the generated C code works with tcc.')
		exit(0)
	}
	if os.user_os() != 'linux' && os.getenv('FORCE_VALGRIND_TEST').len == 0 {
		eprintln('Valgrind tests can only be run reliably on Linux for now.')
		eprintln('You can still do it by setting FORCE_VALGRIND_TEST=1 .')
		exit(0)
	}
	bench_message := 'memory leak checking with valgrind'
	mut bench := benchmark.new_benchmark()
	eprintln(term.header(bench_message, '-'))
	vexe := os.getenv('VEXE')
	vroot := os.dir(vexe)
	dir := os.join_path(vroot,'vlib/v/tests/valgrind')
	files := os.ls(dir) or {
		panic(err)
	}
	//
	wrkdir := os.join_path(os.temp_dir(),'vtests','valgrind')
	os.mkdir_all(wrkdir)
	os.chdir(wrkdir)
	//
	tests := files.filter(it.ends_with('.vv'))
	bench.set_total_expected_steps(tests.len)
	for test in tests {
		bench.step()
		full_test_path := os.real_path(test)
		println('x.v: $wrkdir/x.v')
		os.system('cp ${dir}/${test} $wrkdir/x.v') // cant run .vv file
		res := os.exec('$vexe -cflags "-w" -verbose=3 -b v2 -csource keep -cg $wrkdir/x.v') or {
			bench.fail()
			eprintln(bench.step_message_fail('valgrind $test failed'))
			continue
		}
		if res.exit_code != 0 {
			bench.fail()
			eprintln(bench.step_message_fail('file: $full_test_path could not be compiled.'))
			eprintln(res.output)
			continue
		}
		valgrind_res := os.exec('valgrind --error-exitcode=1 --leak-check=full $wrkdir/x') or {
			bench.fail()
			eprintln(bench.step_message_fail('valgrind could not be executed'))
			continue
		}
		if valgrind_res.exit_code != 0 {
			bench.fail()
			eprintln(bench.step_message_fail('failed valgrind check for $test'))
			eprintln(valgrind_res.output)
			continue
		}
		bench.ok()
		eprintln(bench.step_message_ok('testing file: $test'))
	}
	bench.stop()
	eprintln(term.h_divider('-'))
	eprintln(bench.total_message(bench_message))
	if bench.nfail > 0 {
		exit(1)
	}
}
