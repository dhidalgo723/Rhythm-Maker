class_name RogueRun
extends RefCounted

## Una partida del modo roguelike: las 10 canciones, el dinero, la ranura, las
## flechas mejoradas, los consumibles pendientes y la tienda.
##
## Todo lo aleatorio sale de `seed`: misma semilla, misma partida (mismos jefes,
## mismas canciones, mismas ofertas). Util para probar y para repetir una.

enum State { MAP, SHOP, WON, LOST }

const START_MONEY := 0

var seed := 0
var pool: RoguePool
var state := State.MAP
## Cancion actual (0..9).
var index := 0
var money := 0
## Mejora de ranura ("" = vacia).
var slot_id := ""
## Mejoras de flecha: carril -> {"id": String, "songs_left": int (-1 = siempre)}.
var arrows := {}
## Consumibles comprados para la siguiente cancion.
var pending: Array[String] = []
var bosses: Array[RogueBoss] = []
## Las 3 cajas de la tienda (izquierda, centro, derecha):
## {"kind": ItemKind, "id": String, "sold": bool}.
var offers: Array[Dictionary] = []
## Resultado de la ultima cancion: lo que devuelve finish_song() (pantalla de
## resultados y mapa).
var last_result := {}
## Jefes superados en esta partida.
var bosses_beaten := 0

var _rng := RandomNumberGenerator.new()


static func create(song_pool: RoguePool, run_seed: int = -1) -> RogueRun:
	var run := RogueRun.new()
	run.pool = song_pool
	run.seed = run_seed if run_seed >= 0 else randi()
	run._rng.seed = run.seed
	run.money = START_MONEY
	run._generate_bosses()
	return run


func current_boss() -> RogueBoss:
	return bosses[index] if index < bosses.size() else null


func is_over() -> bool:
	return state == State.WON or state == State.LOST


func songs_total() -> int:
	return RogueCatalog.SEQUENCE.size()


## Generador propio de la cancion `index`: no depende de cuantas veces se haya
## tirado el dado antes (comprar en la tienda no cambia al jefe siguiente).
func rng_for(purpose: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d:%s" % [seed, index, purpose])
	return r


# ---------------------------------------------------------------- Jefes

func _generate_bosses() -> void:
	bosses.clear()
	var used_abilities := {}
	var used_songs := {}
	var combos := RogueCatalog.FINAL_COMBOS.keys()
	for i in RogueCatalog.SEQUENCE.size():
		var boss := RogueBoss.new()
		boss.index = i
		boss.size = RogueCatalog.SEQUENCE[i]
		if boss.size == RogueCatalog.Size.FINAL:
			boss.combo_id = combos[_rng.randi_range(0, combos.size() - 1)]
			boss.abilities.assign(RogueCatalog.FINAL_COMBOS[boss.combo_id]["abilities"])
		else:
			boss.abilities.append(_pick_ability(boss.size, used_abilities))
		boss.song_id = _pick_song(boss.size, used_songs)
		# Los jefes pequenos y medianos se ven desde el principio; los grandes y
		# el final solo al empezar su cancion (o con un Setlist).
		boss.revealed = boss.size in RogueCatalog.VISIBLE_SIZES
		bosses.append(boss)


## Habilidad al azar de ese tamano, sin repetir mientras queden sin usar.
func _pick_ability(size: RogueCatalog.Size, used: Dictionary) -> String:
	var options := RogueCatalog.abilities_of_size(size)
	var fresh: Array[String] = []
	for a in options:
		if not used.has(a):
			fresh.append(a)
	if fresh.is_empty():
		fresh = options
	var pick := fresh[_rng.randi_range(0, fresh.size() - 1)]
	used[pick] = true
	return pick


## Cancion al azar de ese tamano, sin repetir mientras queden.
func _pick_song(size: RogueCatalog.Size, used: Dictionary) -> String:
	if pool == null:
		return ""
	var options := pool.songs_of_size(RogueCatalog.SIZE_KEYS[size])
	if options.is_empty():
		return ""
	var fresh: Array[Dictionary] = []
	for s in options:
		if not used.has(s["id"]):
			fresh.append(s)
	if fresh.is_empty():
		fresh = options
	var pick: Dictionary = fresh[_rng.randi_range(0, fresh.size() - 1)]
	used[pick["id"]] = true
	return pick["id"]


# ---------------------------------------------------------------- Cancion

## Lo necesario para jugar la cancion actual (gasta los consumibles pendientes).
func prepare_song() -> RoguePrepared:
	var prepared := RogueBuilder.build(self)
	if prepared != null:
		current_boss().revealed = true
		pending.clear()
	return prepared


## Cierra la cancion actual. `result`: {score, misses, lost (bool), coin_perfects
## (PackedInt32Array), y para el mapa accuracy, perfects y max_combo}.
## Devuelve lo que paso: {passed, money, reason} mas las cifras de la cancion
## (boss_index, score, target, misses, miss_limit, accuracy, perfects, max_combo).
func finish_song(prepared: RoguePrepared, result: Dictionary) -> Dictionary:
	var out := {
		"passed": false, "money": 0, "reason": "",
		"boss_index": index,
		"score": int(result.get("score", 0)), "target": prepared.target_score,
		"misses": int(result.get("misses", 0)), "miss_limit": prepared.rules.miss_limit,
		"accuracy": float(result.get("accuracy", 0.0)),
		"perfects": int(result.get("perfects", 0)), "max_combo": int(result.get("max_combo", 0)),
	}
	if bool(result.get("lost", false)):
		out["reason"] = Lang.t("Superaste el límite de fallos")
	elif int(result.get("score", 0)) < prepared.target_score:
		out["reason"] = Lang.t("No llegaste a la puntuación (%d de %d)") % [
			int(result.get("score", 0)), prepared.target_score]
	else:
		out["passed"] = true

	if not out["passed"]:
		state = State.LOST
		last_result = out
		return out

	out["money"] = song_reward(prepared, result)
	money += out["money"]
	bosses_beaten += 1
	_age_arrows()
	index += 1
	if index >= songs_total():
		state = State.WON
	else:
		state = State.SHOP
		roll_offers()
	last_result = out
	return out


## Dinero por pasar la cancion: base + bono por los fallos que sobraron, mas
## las monedas de Flecha Hucha, x Contrato y menos el Impuesto.
func song_reward(prepared: RoguePrepared, result: Dictionary) -> int:
	var size := prepared.boss.size
	var limit := maxi(1, prepared.rules.miss_limit)
	var spare := clampf(1.0 - float(result.get("misses", 0)) / limit, 0.0, 1.0)
	var coins := float(RogueCatalog.REWARD_BASE[size]) + roundf(RogueCatalog.REWARD_BONUS[size] * spare)

	var perfects: PackedInt32Array = result.get("coin_perfects", PackedInt32Array())
	var per_coin: int = RogueCatalog.ARROW["hucha"]["perfects_per_coin"]
	for lane in perfects.size():
		coins += perfects[lane] / per_coin

	coins = roundf(coins * prepared.money_mult)
	if prepared.tax > 0.0 and coins > 0.0:
		coins -= ceilf(coins * prepared.tax)   # al menos una moneda: si no, el 2,5% nunca se notaria
	return maxi(0, int(coins))


## Las mejoras de flecha con duracion (Dorada: 3 canciones) se gastan.
func _age_arrows() -> void:
	for lane in arrows.keys():
		var data: Dictionary = arrows[lane]
		if int(data["songs_left"]) > 0:
			data["songs_left"] = int(data["songs_left"]) - 1
			if int(data["songs_left"]) == 0:
				arrows.erase(lane)


# ---------------------------------------------------------------- Tienda

const _KIND_KEYS := {
	"slot": RogueCatalog.ItemKind.SLOT,
	"arrow": RogueCatalog.ItemKind.ARROW,
	"consumable": RogueCatalog.ItemKind.CONSUMABLE,
}


## Rellena las 3 cajas: el tipo de cada una sale de su probabilidad en
## RogueCatalog.SHOP_BOXES, y nunca se repite un objeto ni sale la mejora de
## ranura que ya llevas.
func roll_offers() -> void:
	var r := rng_for("shop:%d" % hash(offers))
	offers.clear()
	var taken := {slot_id: true}
	for box: Dictionary in RogueCatalog.SHOP_BOXES:
		var kind := _roll_kind(r, box)
		var ids: Array = []
		for id in RogueCatalog.table(kind):
			if not taken.has(id):
				ids.append(id)
		var id: String = ids[r.randi_range(0, ids.size() - 1)]
		taken[id] = true
		offers.append({"kind": kind, "id": id, "sold": false})


static func _roll_kind(r: RandomNumberGenerator, box: Dictionary) -> RogueCatalog.ItemKind:
	var roll := r.randf()
	var acc := 0.0
	var last := ""
	for key in box:
		acc += float(box[key])
		last = key
		if roll < acc:
			return _KIND_KEYS[key]
	return _KIND_KEYS[last]


func price(offer: Dictionary) -> int:
	return int(RogueCatalog.item(offer["kind"], offer["id"]).get("price", 0))


## Compra una oferta. `lane` solo para mejoras de flecha. Devuelve "" si fue
## bien o el motivo por el que no.
func buy(offer_index: int, lane: int = -1) -> String:
	if offer_index < 0 or offer_index >= offers.size():
		return Lang.t("Esa oferta no existe")
	var offer := offers[offer_index]
	if offer["sold"]:
		return Lang.t("Ya lo compraste")
	var cost := price(offer)
	if cost > money:
		return Lang.t("No tienes dinero suficiente")
	var kind: RogueCatalog.ItemKind = offer["kind"]
	var id: String = offer["id"]
	if kind == RogueCatalog.ItemKind.ARROW and (lane < 0 or lane >= Lanes.COUNT):
		return Lang.t("Elige en qué flecha ponerla")

	money -= cost
	offer["sold"] = true
	match kind:
		RogueCatalog.ItemKind.SLOT:
			slot_id = id   # solo hay una ranura: sustituye a la anterior
		RogueCatalog.ItemKind.ARROW:
			arrows[lane] = {"id": id, "songs_left": int(RogueCatalog.ARROW[id]["songs"])}
		RogueCatalog.ItemKind.CONSUMABLE:
			if id == "setlist":
				_use_setlist()
			else:
				pending.append(id)
	return ""


## Setlist: al momento. Revela el siguiente jefe y renueva la tienda.
func _use_setlist() -> void:
	var boss := current_boss()
	if boss != null:
		boss.revealed = true
	roll_offers()


func arrow_on(lane: int) -> String:
	return str(arrows[lane]["id"]) if arrows.has(lane) else ""
