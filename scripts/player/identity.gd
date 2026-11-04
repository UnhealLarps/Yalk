extends RefCounted

const PRIVATE_KEY_PATH := "user://identity.key"
const BANLIST_PATH := "user://banlist.json"
const RSA_BITS := 2048
const CHALLENGE_SIZE := 32

var crypto := Crypto.new()
var private_key: CryptoKey
var bans: Array[Dictionary] = []

func initialize() -> bool:
	if FileAccess.file_exists(PRIVATE_KEY_PATH):
		var loaded_key := CryptoKey.new()
		if loaded_key.load(PRIVATE_KEY_PATH) == OK and not loaded_key.is_public_only():
			private_key = loaded_key
	if private_key == null:
		private_key = crypto.generate_rsa(RSA_BITS)
		if private_key == null or private_key.is_public_only():
			return false
		if private_key.save(PRIVATE_KEY_PATH) != OK:
			private_key = null
			return false
	return true

func is_ready() -> bool:
	return private_key != null and not private_key.is_public_only()

func get_public_key_pem() -> String:
	if not is_ready():
		return ""
	return private_key.save_to_string(true)

func generate_challenge() -> PackedByteArray:
	return crypto.generate_random_bytes(CHALLENGE_SIZE)

func sign_challenge(challenge: PackedByteArray) -> PackedByteArray:
	if not is_ready() or challenge.size() != CHALLENGE_SIZE:
		return PackedByteArray()
	return crypto.sign(HashingContext.HASH_SHA256, _sha256(challenge), private_key)

func verify_challenge(public_key_pem: String, challenge: PackedByteArray, signature: PackedByteArray) -> bool:
	if public_key_pem.is_empty() or public_key_pem.length() > 8192 or challenge.size() != CHALLENGE_SIZE or signature.is_empty() or signature.size() > 1024:
		return false
	var public_key := CryptoKey.new()
	if public_key.load_from_string(public_key_pem, true) != OK or not public_key.is_public_only():
		return false
	return crypto.verify(HashingContext.HASH_SHA256, _sha256(challenge), signature, public_key)

func get_fingerprint(public_key_pem: String) -> String:
	if public_key_pem.is_empty() or public_key_pem.length() > 8192:
		return ""
	var public_key := CryptoKey.new()
	if public_key.load_from_string(public_key_pem, true) != OK or not public_key.is_public_only():
		return ""
	var canonical_pem := public_key.save_to_string(true)
	return _sha256(canonical_pem.to_utf8_buffer()).hex_encode()

func load_banlist() -> bool:
	bans.clear()
	if not FileAccess.file_exists(BANLIST_PATH):
		return true
	var file := FileAccess.open(BANLIST_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("bans", [])) != TYPE_ARRAY:
		return false
	for entry_value in parsed.get("bans", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			bans.clear()
			return false
		var entry: Dictionary = entry_value
		var fingerprint: String = str(entry.get("fingerprint", "")).to_lower()
		if not _is_valid_fingerprint(fingerprint):
			bans.clear()
			return false
		var normalized_entry := entry.duplicate(true)
		normalized_entry["fingerprint"] = fingerprint
		bans.append(normalized_entry)
	return true

func is_banned(fingerprint: String) -> bool:
	for entry in bans:
		if str(entry.get("fingerprint", "")) == fingerprint:
			return true
	return false

func add_ban(fingerprint: String, nickname: String, reason: String) -> bool:
	if not _is_valid_fingerprint(fingerprint) or is_banned(fingerprint):
		return false
	bans.append({
		"fingerprint": fingerprint,
		"nickname": nickname.substr(0, 24),
		"reason": reason.substr(0, 160),
		"created_at": int(Time.get_unix_time_from_system())
	})
	if _save_banlist():
		return true
	bans.pop_back()
	return false

func remove_ban(fingerprint_prefix: String) -> Dictionary:
	var query := fingerprint_prefix.strip_edges().to_lower()
	if query.length() < 8:
		return {"success": false, "reason": "Fingerprint prefix must contain at least 8 characters"}
	var match_index := -1
	for i in range(bans.size()):
		var fingerprint := str(bans[i].get("fingerprint", ""))
		if fingerprint.begins_with(query):
			if match_index >= 0:
				return {"success": false, "reason": "Fingerprint prefix is ambiguous; provide more characters"}
			match_index = i
	if match_index < 0:
		return {"success": false, "reason": "Ban not found"}
	var removed: Dictionary = bans.pop_at(match_index)
	if _save_banlist():
		return {"success": true, "fingerprint": str(removed.get("fingerprint", ""))}
	bans.insert(match_index, removed)
	return {"success": false, "reason": "Failed to write banlist.json"}

func _save_banlist() -> bool:
	var file := FileAccess.open(BANLIST_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "bans": bans}, "\t"))
	var error := file.get_error()
	file.close()
	return error == OK

func _is_valid_fingerprint(value: String) -> bool:
	if value.length() != 64:
		return false
	for i in range(value.length()):
		if not "0123456789abcdef".contains(value.substr(i, 1)):
			return false
	return true

func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if context.update(data) != OK:
		return PackedByteArray()
	return context.finish()
