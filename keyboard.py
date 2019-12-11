from pynput.keyboard import Key, Controller
import socket
from AppKit import NSWorkspace

keyboard = Controller()
s = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.bind(('', 7673))
s.listen(1)

print('Waiting for client')
(clientsocket, address) = s.accept()
print("Client connected")

try:
	while True:
		data = clientsocket.recv(1024)
		if not data: break
		data = data.decode()
		print("Received: "+data)
		activeWindow = NSWorkspace.sharedWorkspace().activeApplication()['NSApplicationName']
		print(activeWindow)
		if data[0]=='d':
			if activeWindow=='iTunes':
				print("Skipping")
				with keyboard.pressed(Key.cmd):
					keyboard.press(Key.right)
					keyboard.release(Key.right)
			else:
				keyboard.press(Key.page_down)
				keyboard.release(Key.page_down)
		elif data[0]=='u':
			if activeWindow=='iTunes':
				print("Pausing")
				keyboard.press(Key.space)
				keyboard.release(Key.space)
			else:
				keyboard.press(Key.page_up)
				keyboard.release(Key.page_up)
finally:
	print('shutting down')
	clientsocket.close()
	s.close()
