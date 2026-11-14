extends TestCase

const FIXTURES := "res://tests/fixtures/registry/"

func after_each() -> void:
	Registry.scan()

func _scan(root: String) -> PackedStringArray:
	return quietly(func() -> PackedStringArray: return Registry.scan(root))

func test_fetch_by_id_and_duplicate_reports_error() -> void:
	var problems := _scan(FIXTURES + "data")
	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_true(problems.size() == 1 and problems[0].contains("duplicate id"), "\n".join(problems))
	assert_eq(Registry.fetch(&"items", &"b").id, &"b")
	assert_eq(Registry.ids(&"items").size(), 2)

func test_duplicate_id_keeps_the_first_and_names_both_files() -> void:
	var problems := _scan(FIXTURES + "data")
	var first: Resource = Registry.fetch(&"items", &"a")
	assert_eq(first.resource_path, FIXTURES + "data/items/a.tres", "a.tres sorts before dup.tres, so it is kept")
	assert_true(problems[0].contains("'a'"), problems[0])
	assert_true(problems[0].contains("items/dup.tres") and problems[0].contains("items/a.tres"), problems[0])

func test_ids_lists_a_kinds_ids() -> void:
	_scan(FIXTURES + "data")
	assert_eq(Registry.ids(&"items"), PackedStringArray(["a", "b"]))
	assert_eq(Registry.ids(&"nothing"), PackedStringArray())

func test_fetch_returns_the_same_resource_each_time() -> void:
	_scan(FIXTURES + "data")
	assert_true(Registry.fetch(&"items", &"b") == Registry.fetch(&"items", &"b"))

func test_missing_id_errors_and_returns_null() -> void:
	_scan(FIXTURES + "data")
	assert_eq(quietly(func(): return Registry.fetch(&"items", &"zzz")), null)
	assert_eq(quietly(func(): return Registry.fetch(&"weapons", &"a")), null, "an unknown kind is a missing id")

func test_scan_without_problems_returns_nothing() -> void:
	assert_eq(_scan(FIXTURES + "nested"), PackedStringArray())

func test_scan_recurses_and_the_kind_is_the_first_folder() -> void:
	_scan(FIXTURES + "nested")
	assert_eq(Registry.ids(&"props"), PackedStringArray(["deep", "top"]))
	assert_eq(Registry.fetch(&"props", &"deep").resource_path, FIXTURES + "nested/props/sub/deep.tres")
	assert_eq(Registry.ids(&"sub"), PackedStringArray(), "a subfolder is not a kind")

func test_resources_without_an_id_property_are_not_registered() -> void:
	_scan(FIXTURES + "nested")   # props/plain.tres is a bare Resource
	assert_eq(Registry.ids(&"props").size(), 2)

func test_an_empty_id_is_reported_and_not_registered() -> void:
	var problems := _scan(FIXTURES + "blank")
	assert_eq(problems.size(), 1, "\n".join(problems))
	assert_true(problems.size() == 1 and problems[0].contains("empty id") and problems[0].contains("blank.tres"), "\n".join(problems))
	assert_eq(Registry.ids(&"props"), PackedStringArray())

func test_scan_replaces_the_index() -> void:
	_scan(FIXTURES + "data")
	_scan(FIXTURES + "nested")
	assert_eq(Registry.ids(&"items"), PackedStringArray())
	assert_eq(Registry.ids(&"props").size(), 2)

func test_scanning_a_folder_that_is_not_there_finds_nothing() -> void:
	_scan(FIXTURES + "data")
	assert_eq(_scan(FIXTURES + "no_such_folder"), PackedStringArray())
	assert_eq(Registry.ids(&"items"), PackedStringArray())
