;;; clipmon.el --- Clipboard monitor - automatically pastes clipboard changes.
;;; About:
;;
;; Copyright (C) 2014 Brian Burns
;;
;; Author: Brian Burns <bburns.km@gmail.com>
;; Homepage: https://github.com/bburns/clipmon
;;
;; Version: 0.1.20141219
;; Keywords: convenience
;; Created: 2014-02-21
;; License: GPLv3
;;
;; This file is NOT part of GNU Emacs.
;;
;;
;;; Commentary:
;;
;;;; Description
;;
;; Clipmon monitors the system clipboard and pastes any changes into the current
;; location in Emacs.
;;
;; This makes it easier to take notes from a webpage, for example - just copy
;; the text you wish to save. You can still use the Emacs kill-ring with yank
;; and pull as usual, as clipmon only looks at the system clipboard.
;;
;; Works best when paired with an autocopy feature or plugin for the browser,
;; e.g. AutoCopy 2 for Firefox - then you can just select text to copy it to the
;; clipboard.
;;
;;
;;;; Usage
;;
;; Make a key-binding like the following to turn clipmon on and off:
;;
;;     (global-set-key (kbd "<M-f2>") 'clipmon-toggle)
;;
;; Then turn it on and go to another application, like a browser, and copy some
;; text to the clipboard. Clipmon should detect it after a second or two, and
;; make a sound. If you switch back to Emacs, it should have pasted the text
;; into your buffer.
;;
;;
;;;; Options
;;
;; Once started, clipmon checks the clipboard for changes every
;; `clipmon-interval' seconds (default 2). If no change is detected after
;; `clipmon-timeout' minutes (default 5), clipmon will turn itself off
;; automatically.
;;
;; The cursor color can be set with `clipmon-cursor-color' - eg "red", or nil
;; for no change.
;;
;; A sound can be played on each change, and on starting and stopping clipmon.
;; The sound can be set with `clipmon-sound' - this can be a filename (.wav or
;; .au), t for the default Emacs beep/flash, or nil for no sound.
;;
;; When selecting text to copy, it's sometimes difficult to avoid grabbing a
;; leading space - to remove these from the text, set `clipmon-trim-string' to t
;; (on by default).
;;
;; To filter the text some more set `clipmon-remove-regexp' - it will remove any
;; matching text before pasting. By default it is set to remove Wikipedia-style
;; references, e.g. "[3]".
;;
;; You can also have newlines appended to the text - specify the number to add
;; with `clipmon-newlines'. The default is 2, giving a blank line between
;; entries.
;;
;; See all options here: (customize-group 'clipmon)
;;
;;
;;;; Todo
;;
;; - bug - try to start with empty kill ring - gives error on calling
;;   current-kill
;; - test with -Q
;; - package.el
;; - preserve echo message - often gets wiped out
;; - bug - lost timer
;;   when put laptop to sleep with it on, on resuming,
;;   it seemed to lose track of the timer, and couldn't turn it off without
;;   calling (cancel-function-timers 'clipmon--tick)
;;
;;
;;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;
;;; Code:

;;;; Public settings
; -----------------------------------------------------------------------------

(defgroup clipmon nil
  "Clipboard monitor - automatically paste clipboard changes."
  :group 'convenience
  :group 'killing
  :version "24.4"
  )

; --

(defcustom clipmon-cursor-color "red"
  "Color to set cursor when clipmon is on. Set to nil for no change."
  :group 'clipmon
  :type 'color
  )

(defcustom clipmon-sound t
  "Sound to play when pasting text: path to a sound file, t for beep, or nil.
Use t for the default Emacs beep, or nil for none. Can play .wav or .au files."
  :group 'clipmon
  :type '(radio (string :tag "Audio file") (boolean :tag "Default beep"))
  )

(defcustom clipmon-interval 2
  "Interval for checking clipboard, in seconds."
  :group 'clipmon
  :type 'integer
  )

(defcustom clipmon-timeout 5
  "Stop the timer if no clipboard activity after this many minutes.
Set to nil for no timeout."
  :group 'clipmon
  :type 'integer
  )

(defcustom clipmon-trim-string t
  "Remove leading whitespace from string before pasting if non-nil.
Often it's hard to select text without grabbing a leading space,
so this will remove it for you."
  :group 'clipmon
  :type 'boolean
  )

(defcustom clipmon-remove-regexp
  "\\[[0-9]+\\]\\|\\[citation needed\\]\\|\\[by whom?\\]"
  "Any text matching this regexp will be removed before pasting.
e.g. Wikipedia-style references - [3], [12]."
  :group 'clipmon
  :type 'regexp
  )

(defcustom clipmon-newlines 2
  "Number of newlines to append to text before pasting."
  :group 'clipmon
  :type 'integer
  )



;;;; Private variables
; -----------------------------------------------------------------------------

(defvar clipmon--timer nil "Timer handle for clipboard monitor.")
(defvar clipmon--timeout-start nil "Time that timeout timer was started.")
(defvar clipmon--previous-contents nil "Last contents of the clipboard.")
(defvar clipmon--cursor-color-original nil "Original cursor color.")



;;;; Public functions
; -----------------------------------------------------------------------------

;;;###autoload
(defun clipmon-toggle ()
  "Turn clipmon on and off (clipboard monitor/autopaste)."
  (interactive)
  (if clipmon--timer (clipmon-stop) (clipmon-start)))


(defun clipmon-start ()
  "Start the clipboard timer, change cursor color, and play a sound."
  (interactive)
  (let ((clipmon-keys (get-function-keys 'clipmon-toggle))) ; eg "<M-f2>, C-0"
    (if clipmon--timer
        (message "Clipboard monitor already running. Stop with %s." clipmon-keys)
      ; initialize
      (setq clipmon--previous-contents (clipboard-contents))
      (setq clipmon--timeout-start (current-time))
      (setq clipmon--timer (run-at-time nil clipmon-interval 'clipmon--tick))
      ; change cursor color
      (when clipmon-cursor-color
        (setq clipmon--cursor-color-original (face-background 'cursor))
        (set-face-background 'cursor clipmon-cursor-color)
        )
      (message
       "Clipboard monitor started with timer interval %d seconds. Stop with %s."
       clipmon-interval clipmon-keys)
      (clipmon--play-sound)
      )))


(defun clipmon-stop ()
  "Stop the clipboard monitor timer."
  (interactive)
  (cancel-timer clipmon--timer)
  (setq clipmon--timer nil)
  (if clipmon--cursor-color-original
      (set-face-background 'cursor clipmon--cursor-color-original))
  (message "Clipboard monitor stopped.")
  (clipmon--play-sound)
  )



;;;; Private functions
; -----------------------------------------------------------------------------

(defun clipmon--tick ()
  "Check the contents of the clipboard and paste it if changed.
Otherwise stop clipmon if it's been idle a while."
  (let ((s (clipboard-contents))) ; s may actually be nil here
    (if (and s (not (string-equal s clipmon--previous-contents))) ; if changed
        (clipmon--paste s)
        ; otherwise stop monitor if it's been idle a while
        (if clipmon-timeout
            (let ((idletime (seconds-since clipmon--timeout-start)))
              (when (> idletime (* 60 clipmon-timeout))
                (clipmon-stop)
                (message
                 "Clipboard monitor stopped after %d minutes of inactivity."
                 clipmon-timeout)
                )))
        )))


(defun clipmon--paste (s)
  "Insert the string s at the current location, play sound, update state."
  (setq clipmon--previous-contents s) ; save contents
  (if clipmon-trim-string (setq s (trim-left s)))
  (if clipmon-remove-regexp
      (setq s (replace-regexp-in-string clipmon-remove-regexp "" s)))
  (insert s) ; paste it
  (dotimes (i clipmon-newlines) (insert "\n"))
  (if clipmon-sound (clipmon--play-sound))
  (setq clipmon--timeout-start (current-time))) ; restart timeout timer


(defun clipmon--play-sound ()
  "Play a sound file, the default beep (or screen flash), or nothing."
  (if clipmon-sound
      (if (stringp clipmon-sound) (play-sound-file clipmon-sound) (beep))))



;;;; Library functions
; -----------------------------------------------------------------------------

(defun clipboard-contents ()
  "Get contents of system clipboard, as opposed to Emacs's kill ring.
Returns a string, or nil."
  (x-get-selection-value))


(defun get-function-keys (function)
  "Get list of keys bound to a function, as a string.
e.g. (get-function-keys 'ibuffer) => \"C-x C-b, <menu-bar>...\""
  (mapconcat 'key-description (where-is-internal function) ", "))


(defun trim-left (s)
  "Remove any leading spaces from s."
  (replace-regexp-in-string  "^[ \t]+"  ""  s))


(defun seconds-since (time)
  "Return number of seconds elapsed since the given time.
Time should be in Emacs time format (see `current-time').
Valid for up to 2**16 seconds = 65536 secs = 18hrs."
  (cadr (time-subtract (current-time) time)))


;;;; Provide

(provide 'clipmon)

;;; clipmon.el ends here
