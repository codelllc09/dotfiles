;;; init-ime.el --- English input for Emacs command prefixes -*- lexical-binding: t; -*-

(defun lcw-ime--english ()
  "Deactivate Fcitx 5 for the focused, interactive frame."
  (when (and (not noninteractive)
             (not executing-kbd-macro)
             (frame-focus-state))
    (let ((default-directory temporary-file-directory))
      (condition-case nil
          (call-process "busctl" nil nil nil
                        "--user" "--auto-start=no" "--timeout=150ms" "call"
                        "org.fcitx.Fcitx5" "/controller"
                        "org.fcitx.Fcitx.Controller1" "Deactivate")
        (file-error nil)))))

(defun lcw-ime--maybe-prefix (keys)
  "Switch to English if KEYS is a keyboard prefix in the active maps."
  (when (and (> (length keys) 0)
             ;; A literal ESC can be the first byte of an ordinary Meta key.
             (not (and (= (length keys) 1)
                       (eq (aref keys 0) meta-prefix-char)))
             (not (seq-some #'consp keys))
             (keymapp (key-binding keys t t)))
    (lcw-ime--english)))

(defun lcw-ime--at-raw-key-p (keys)
  "Return non-nil if the translation is considering the newest raw key."
  (and (> (length keys) 0)
       (equal (aref keys (1- (length keys)))
              (aref current-key-remap-sequence 0))))

(defun lcw-ime--raw-prefix (_prompt)
  "Check prefixes that later translation maps keep pending."
  (let ((keys (this-single-command-raw-keys)))
    (when (and (lcw-ime--at-raw-key-p keys)
               (or (keymapp (lookup-key local-function-key-map keys))
                   (keymapp (lookup-key key-translation-map keys))))
      (lcw-ime--maybe-prefix keys)))
  ;; Returning nil does not translate the event.
  nil)

(defun lcw-ime--decoded-prefix (_prompt)
  "Check an active prefix after terminal key decoding."
  (let ((keys (this-single-command-keys))
        (raw (this-single-command-raw-keys)))
    (cond
     ((equal keys current-key-remap-sequence)
      (lcw-ime--maybe-prefix keys))
     ((lcw-ime--at-raw-key-p raw)
      (lcw-ime--maybe-prefix raw))))
  nil)

(defun lcw-ime--install-decoder (frame)
  "Install the prefix observer in FRAME's terminal decode map."
  (with-selected-frame frame
    (unless (lookup-key input-decode-map [t])
      (define-key input-decode-map [t] #'lcw-ime--raw-prefix))))

(defun lcw-ime--before-command ()
  "Switch to English before command selection and prefix arguments."
  (when (memq this-command '(execute-extended-command
                             execute-extended-command-for-buffer
                             universal-argument digit-argument negative-argument))
    (lcw-ime--english)))

;; Observe lookup through the default translations and leave explicit
;; translations such as C-x 8 and C-x @ in place.
(dolist (frame (frame-list))
  (lcw-ime--install-decoder frame))
(add-hook 'after-make-frame-functions #'lcw-ime--install-decoder)
(unless (lookup-key key-translation-map [t])
  (define-key key-translation-map [t] #'lcw-ime--decoded-prefix))
(add-hook 'pre-command-hook #'lcw-ime--before-command)

(provide 'init-ime)
;;; init-ime.el ends here
