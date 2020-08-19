extends Popup

onready var _edit = find_node("LineEdit")
onready var _results_list = find_node("SearchResultsList")

func _ready():
	_results_list.connect("item_activated", self, "_on_results_item_activated")
	_edit.connect("text_changed", self, "_on_search_text_changed")
	
func _on_search_text_changed(text):
	if text == "":
		self._prepare_results_list(null)
	else: 
		self._prepare_results_list(text)

func _on_results_item_activated(ix):
	var id = _results_list.get_item_metadata(ix)
	Slack.select_conversation(id)
	self.hide()

func _prepare_results_list(search_term):
	_results_list.clear()
	var channels = Slack._state.channels.values()
	var ix = 0
	for c in channels:
		if search_term == null || c.name.begins_with(search_term):
			_results_list.add_item(c.name)
			_results_list.set_item_metadata(ix, c.id)
			ix += 1
	var gs = Slack._state.groups.values()
	for g in gs:
		if search_term == null || g.name.begins_with(search_term):
			_results_list.add_item(g.name)
			_results_list.set_item_metadata(ix, g.id)
			ix += 1
	for m in Slack._state.ims.values():
		var username = Slack.fd(Slack._state, ["users", m.user, "name"])
		if search_term == null || username.begins_with(search_term):
			_results_list.add_item(username)
			_results_list.set_item_metadata(ix, m.id)
			ix += 1

func _prepare_popup():
	_edit.clear()
	self._prepare_results_list(null)
		
func _input(event):
	if Input.is_action_pressed("ui_search"):
		self._prepare_popup()
		self.popup()
