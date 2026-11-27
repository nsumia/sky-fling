extends "res://tests/base.gd"
## Asset test: every shipped file under assets/ is listed in ASSETS.md with a CC0 / CC-BY 3.0 licence, every listed file exists,
## every res://assets path used by a script is listed, and the Credits screen text carries every CC-BY attribution.
const Credits = preload("res://scripts/core/credits.gd")

func _initialize() -> void:
	run.call_deferred()

func files_under(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		files_under(dir.path_join(d), out)

func run() -> void:
	var md := FileAccess.get_file_as_string("res://ASSETS.md")
	check("ASSETS.md exists", md.length() > 200)
	var listed: Array = []      # repo-relative paths ("assets/...")
	var cc_by: Array = []       # [name, author]
	var bad_lic := 0
	var rows := 0
	for line in md.split("\n"):
		if not line.begins_with("| ") or line.begins_with("| Name") or line.begins_with("|---"):
			continue
		var cols := line.split("|")
		if cols.size() < 8:
			continue
		rows += 1
		var lic := cols[4].strip_edges()
		if not (lic.begins_with("CC0") or lic.begins_with("CC-BY 3.0")):
			bad_lic += 1
			print("bad licence in row: ", line.left(80))
		if lic.begins_with("CC-BY"):
			cc_by.append([cols[1].strip_edges(), cols[2].strip_edges()])
		for part in cols[5].split("`"):
			if part.begins_with("assets/"):
				listed.append(part)
	check("ASSETS.md has asset rows (%d)" % rows, rows >= 20, str(rows))
	check("every row is CC0 or CC-BY 3.0 (no NC / ND / personal use)", bad_lic == 0, str(bad_lic))
	var missing := 0
	for pth in listed:
		var ok: bool = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + pth)) if pth.ends_with("/") else FileAccess.file_exists("res://" + pth)
		if not ok:
			missing += 1
			print("listed but missing: ", pth)
	check("every file listed in ASSETS.md exists (%d entries)" % listed.size(), missing == 0, str(missing))
	var shipped: Array = []
	files_under("res://assets", shipped)
	var unlisted := 0
	for f in shipped:
		var rel: String = String(f).trim_prefix("res://")
		var covered := false
		for pth in listed:
			if pth == rel or (pth.ends_with("/") and rel.begins_with(pth)):
				covered = true
				break
		if not covered:
			unlisted += 1
			print("shipped but not in ASSETS.md: ", rel)
	check("every shipped model / texture / HDRI is listed in ASSETS.md (%d files)" % shipped.size(), unlisted == 0, str(unlisted))
	# scripts must only use listed assets
	var used := 0
	var bad_use := 0
	for dir in ["res://scripts/game", "res://scripts/core"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			var re := RegEx.create_from_string("res://assets/[A-Za-z0-9_./-]+\\.[a-z]{2,4}")
			for mt in re.search_all(src):
				used += 1
				var rel2: String = mt.get_string().trim_prefix("res://")
				var cov := false
				for pth in listed:
					if pth == rel2 or (pth.ends_with("/") and rel2.begins_with(pth)):
						cov = true
				if not cov:
					bad_use += 1
					print("script uses an asset not in ASSETS.md: ", rel2)
	check("assets used by scripts are all listed (%d references)" % used, bad_use == 0, str(bad_use))
	# credits
	var ctext: String = Credits.text()
	var lost := 0
	for c in cc_by:
		if ctext.find(String(c[1])) < 0 or ctext.find(String(c[0])) < 0:
			lost += 1
			print("Credits text misses: ", c)
	check("Credits screen carries every CC-BY attribution (%d)" % cc_by.size(), cc_by.size() >= 3 and lost == 0, str(lost))
	check("Credits text names the licence", ctext.find("CC BY 3.0") >= 0)
	print("assets shipped=%d listed entries=%d cc-by rows=%d" % [shipped.size(), listed.size(), cc_by.size()])
	finish("ASSETS")
