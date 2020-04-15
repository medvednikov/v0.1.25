fn test_simple_string_interpolation() {
	a := 'Hello'
	b := 'World'
	res := '$a $b'
	assert res == 'Hello World'
}

fn test_mixed_string_interpolation() {
	num := 7
	str := 'abc'
	s1 := 'number=$num'
	assert s1 == 'number=7'
	s2 := 'string=$str'
	assert s2 == 'string=abc'
	s3 := 'a: $num | b: $str'
	assert s3 == 'a: 7 | b: abc'
}

fn test_formatted_string_interpolation() {
	x := 'abc'
	axb := 'a:$x:b'
	assert axb == 'a:abc:b'
	x_10 := 'a:${x:10s}:b'
	x10_ := 'a:${x:-10s}:b'
	assert x_10 == 'a:       abc:b'
	assert x10_ == 'a:abc       :b'
	i := 23
	si_right := '${i:10d}'
	si__left := '${i:-10d}'
	assert si_right == '        23'
	assert si__left == '23        '
}

fn test_excape_dollar_in_string() {
	i := 42
	assert '($i)' == '(42)'
	assert '(\$i)'.contains('i') && !'(\$i)'.contains('42')
	assert !'(\\$i)'.contains('i') && '(\\$i)'.contains('42') && '(\\$i)'.contains('\\')
	assert '(\\\$i)'.contains('i') && !'(\\\$i)'.contains('42') && '(\\$i)'.contains('\\')
	assert !'(\\\\$i)'.contains('i') && '(\\\\$i)'.contains('42') && '(\\\\$i)'.contains('\\\\')
	assert '(${i})' == '(42)'
	assert '(\${i})'.contains('i') && !'(\${i})'.contains('42')
	assert !'(\\${i})'.contains('i') && '(\\${i})'.contains('42') && '(\\${i})'.contains('\\')
	assert '(\\\${i})'.contains('i') && !'(\\\${i})'.contains('42') && '(\\${i})'.contains('\\')
	assert !'(\\\\${i})'.contains('i') && '(\\\\${i})'.contains('42') && '(\\\\${i})'.contains('\\\\')
	assert i == 42
}

fn test_implicit_str() {
	i := 42
	assert 'int $i' == 'int 42'
	assert '$i' == '42'
	check := '$i' == '42'
	assert check
	text := '$i' + '42'
	assert text == '4242'
}
