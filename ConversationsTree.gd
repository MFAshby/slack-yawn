extends Tree

# Called when the node enters the scene tree for the first time.
func _ready():
	self.connect("item_selected", self, "_item_selected")
	Slack.connect("state_changed", self, "_state_changed")	

func _state_changed(old_state, new_state):
	# https://github.com/godotengine/godot/issues/16174
	self.call_deferred("_rebuild_tree", old_state, new_state)
	
func _rebuild_tree(old_state, new_state):
	if Slack.fd(old_state, ["channels"]) == Slack.fd(new_state,  ["channels"]):
		return
	
	var oldRoot = self.get_root()
	if oldRoot != null:
		oldRoot.call_recursive("free")
	
	var root = self.create_item()
	var starred = self.create_item(root)
	var chans = self.create_item(root)
	var other = self.create_item(root)
	self.set_hide_root(true)
	starred.set_text(0, "Starred")
	chans.set_text(0, "Channels")
	other.set_text(0, "Chats")
	
	starred.get_children()
	# 3 root nodes, 
	# Starred channels, alphabetical
	# Other channels, alphabetical
	# IMs  / Groups, 
	var channels = new_state.channels.values()
	for c in channels:	
		if _is_starred(c.id, new_state):
			var i = self.create_item(starred)
			i.set_text(0, c.name)
			i.set_metadata(0, c)
		else:
			var i = self.create_item(chans)
			i.set_text(0, c.name)
			i.set_metadata(0, c)
	var gs = new_state.groups.values()
	for g in gs:
		var i = self.create_item(other)
		i.set_text(0, g.name)
		i.set_metadata(0, g)
	for m in new_state.ims.values():
		var i = self.create_item(other)
		var username = Slack.fd(new_state, ["users", m.user, "name"])
		i.set_text(0, username)
		i.set_metadata(0, m)

func _is_starred(cid, state):
	return Slack.fd(state, ["stars", cid, "is_channel_starred"])

func _item_selected():
	var i = self.get_selected()
	var m = i.get_metadata(0)
	# Root nodes have no metadata
	if m != null:
		Slack.select_conversation(m.id)
