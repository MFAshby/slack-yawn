extends ItemList

# Called when the node enters the scene tree for the first time.
func _ready():
	self.connect("item_selected", self, "_item_selected")
	Slack.connect("state_changed", self, "_state_changed")

func _state_changed(new_state):
	self.clear()
	var channels = new_state.channels.values()
	for i in len(channels):	
		var channel = channels[i]
		self.add_item(channel.name)
		self.set_item_metadata(i, channel)
	self.sort_items_by_text()

func _item_selected(idx):
	var channel = self.get_item_metadata(idx)
	print("Selecting channel ", channel.id)
	Slack.select_conversation(channel.id)
