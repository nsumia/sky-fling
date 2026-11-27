extends SceneTree
## Tiny test harness: check(name, cond), finish("NAME") prints "== N passed, M failed ==" and "<NAME> OK" and exits non-zero on failure.
var passed := 0
var failed := 0

func check(name: String, cond: bool, info := "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", name, " ", info)

func finish(tag: String) -> void:
	print("== %d passed, %d failed ==" % [passed, failed])
	if failed == 0:
		print(tag, " OK")
		quit(0)
	else:
		print(tag, " FAILED")
		quit(1)
