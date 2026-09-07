import sys
import time

import nfc
import pyautogui


def on_connect(tag):
    nfc_id = tag.identifier.hex()
    print(f"NFC Tag detected with ID: {nfc_id}")
    pyautogui.write(f"nfc{nfc_id}")
    pyautogui.press("Enter")
    return True


def main():
    device = sys.argv[1] if len(sys.argv) > 1 else "usb:072f:2200"
    while True:
        try:
            with nfc.ContactlessFrontend(device) as clf:
                print("Waiting for NFC tag...")
                clf.connect(rdwr={"on-connect": on_connect})
                time.sleep(1)
        except Exception as e:
            print(f"Error: {e}. Retrying in 5 seconds...")
            time.sleep(5)


if __name__ == "__main__":
    main()
