extends ItemList

# Called when the node enters the scene tree for the first time.
func _ready():
	Slack.connect("state_changed", self, "_state_changed")
	
class TimestampSorter:
	static func sort_by_ts_desc(a, b):
		return a["ts"] < b["ts"]
		
func _state_changed(new_state):
	self.clear()
	var c = new_state["selected_conversation"]
	if c != null:
		var f = new_state["fetching_conversation"]
		if f == c:
			self.add_item("Loading...")
		else:
			var messages: Array = new_state.messages[c]
			messages.sort_custom(TimestampSorter, "sort_by_ts_desc")
			for i in len(messages):
				var msg = messages[i]
				self.add_item(msg.text)
	var scrollbar = self.get_v_scroll()
	scrollbar.value = scrollbar.min_value

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
