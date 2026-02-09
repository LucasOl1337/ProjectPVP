import argparse
import json
import socket
import sys
import time


def send_json_line(sock: socket.socket, payload: dict) -> None:
	data = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
	sock.sendall(data)


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--host", default="127.0.0.1")
	parser.add_argument("--port", type=int, default=20001)
	parser.add_argument("--timeout", type=float, default=2.0)
	parser.add_argument("--duration", type=float, default=5.0)
	parser.add_argument("--reply-actions", action="store_true")
	parser.add_argument("--time-scale", type=float, default=1.0)
	parser.add_argument("--watch", action="store_true")
	parser.add_argument("--assert-delta", action="store_true")
	args = parser.parse_args()

	deadline = time.time() + float(args.duration)
	try:
		sock = socket.create_connection((args.host, int(args.port)), timeout=float(args.timeout))
	except OSError as exc:
		print(f"Falha ao conectar em {args.host}:{args.port}: {exc}")
		return 2

	sock.settimeout(float(args.timeout))
	f = sock.makefile("rwb")

	seen = {"hello": False, "step": False, "metrics": False}
	try:
		send_json_line(sock, {"type": "config", "watch_mode": bool(args.watch), "time_scale": float(args.time_scale)})
		send_json_line(sock, {"type": "get_metrics"})
		while time.time() < deadline:
			try:
				line = f.readline()
			except TimeoutError:
				continue
			if not line:
				break
			try:
				msg = json.loads(line.decode("utf-8", errors="ignore").strip())
			except json.JSONDecodeError:
				continue
			if not isinstance(msg, dict):
				continue
			msg_type = str(msg.get("type", ""))
			if msg_type == "hello":
				seen["hello"] = True
			elif msg_type == "step":
				seen["step"] = True
				try:
					obs = msg.get("obs") if isinstance(msg.get("obs"), dict) else {}
					p1 = obs.get("1") if isinstance(obs.get("1"), dict) else {}
					dt = float(p1.get("delta", 0.0) or 0.0)
					print(json.dumps({"step_delta": dt, "time_scale": float(args.time_scale)}, ensure_ascii=False))
					if args.assert_delta:
						if dt <= 0.0:
							print("ERRO: obs.delta <= 0")
							return 4
						if float(args.time_scale) > 1.5 and dt < 0.03:
							print("ERRO: obs.delta parece não refletir time_scale")
							return 5
				except Exception:
					if args.assert_delta:
						print("ERRO: falha ao ler obs.delta")
						return 6
				if args.reply_actions:
					send_json_line(sock, {"type": "action", "actions": {"1": {}, "2": {}}})
			elif msg_type == "metrics":
				seen["metrics"] = True
			print(json.dumps({"type": msg_type, "keys": sorted(list(msg.keys()))}, ensure_ascii=False))
			if seen["step"] and seen["metrics"]:
				break
	finally:
		try:
			f.close()
		except Exception:
			pass
		try:
			sock.close()
		except Exception:
			pass

	if seen["step"]:
		print("OK: recebeu 'step' do jogo")
		return 0
	print("ERRO: não recebeu 'step' dentro do tempo")
	return 3


if __name__ == "__main__":
	sys.exit(main())

