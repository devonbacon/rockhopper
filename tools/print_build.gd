extends Node
## Prints the build hash the server checks, and quits. For tools/export_windows.sh.


func _ready() -> void:
	print("build ", Net.version)
	get_tree().quit()
