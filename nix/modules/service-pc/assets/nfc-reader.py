import subprocess
import sys
import time

import nfc


def on_connect(ydotool, tag):
    nfc_id = tag.identifier.hex()
    print(f"NFC Tag detected with ID: {nfc_id}")
    subprocess.run([ydotool, "type", f"nfc{nfc_id}"], check=True)
    subprocess.run([ydotool, "key", "28:1", "28:0"], check=True)  # Enter
    return True


def main():
    device = sys.argv[1] if len(sys.argv) > 1 else "usb:072f:2200"
    ydotool = sys.argv[2] if len(sys.argv) > 2 else "ydotool"
    while True:
        try:
            with nfc.ContactlessFrontend(device) as clf:
                print("Waiting for NFC tag...")
                clf.connect(rdwr={"on-connect": lambda tag: on_connect(ydotool, tag)})
                time.sleep(1)
        except Exception as e:
            print(f"Error: {e}. Retrying in 5 seconds...")
            time.sleep(5)


if __name__ == "__main__":
    main()
