;;; init-terminal.el --- Project terminal panel (Vterm) -*- lexical-binding: t; -*-

;; A per-project Vterm side panel toggled with C-x w t.  The panel helpers
;; are terminal-only today; if another panel kind ever appears, move them to
;; a shared module.  Runtime dependencies by load order: init-project for
;; `lcw-project-root-or-default', init-ui for the
;; `lcw-terminal-header-label' / `lcw-terminal-header-hint' faces.

(defun lcw-panel-window (kind)
  "Return the visible panel window of KIND in the selected frame."
  (seq-find (lambda (window)
              (eq (window-parameter window 'lcw-panel) kind))
            (window-list (selected-frame))))

(defun lcw-toggle-panel (kind root buffer side size)
  "Toggle or focus the KIND panel for ROOT showing BUFFER.
Place a new panel on SIDE using SIZE as its width or height."
  (let ((window (lcw-panel-window kind)))
    (cond
     ((and window
           (eq window (selected-window))
           (equal root (window-parameter window 'lcw-panel-root)))
      (delete-window window))
     (window
      (set-window-dedicated-p window nil)
      (set-window-buffer window buffer)
      (set-window-parameter window 'lcw-panel-root root)
      (set-window-dedicated-p window t)
      (select-window window))
     (t
      (setq window
            (display-buffer-in-side-window
             buffer
             `((side . ,side)
               (slot . 0)
               (,(if (eq side 'bottom) 'window-height 'window-width)
                . ,size))))
      (set-window-parameter window 'lcw-panel kind)
      (set-window-parameter window 'lcw-panel-root root)
      (set-window-dedicated-p window t)
      (select-window window)))
    ;; Terminal output already supports keyboard scrolling. Keep its dedicated
    ;; side window visually clean without changing scroll bars elsewhere.
    (when (and (eq kind 'terminal) (window-live-p window))
      (set-window-scroll-bars window nil nil nil nil t))
    window))

(use-package vterm
  :if (locate-library "vterm")
  :commands vterm-mode
  :custom
  (vterm-max-scrollback 10000)
  (vterm-kill-buffer-on-exit t))

(defun lcw-vterm-process-environment ()
  "Return an environment without inherited WezTerm-only integration flags."
  (seq-remove
   (lambda (entry)
     (string-match-p
      "\\`\\(?:WEZTERM_[^=]*\\|TERM_PROGRAM\\(?:_VERSION\\)?\\)=" entry))
   process-environment))

(defun lcw-vterm-header-line ()
  "Return the contextual header used by the bottom Vterm panel."
  (list
   " "
   (propertize
    (format "%s VTERM  %s"
            (if (fboundp 'nerd-icons-codicon)
                (substring-no-properties
                 (nerd-icons-codicon "nf-cod-terminal"))
              ">_")
            (abbreviate-file-name default-directory))
    'face 'lcw-terminal-header-label)
   mode-line-format-right-align
   (propertize "C-x w t  close " 'face 'lcw-terminal-header-hint)))

(defun lcw-project-vterm-buffer (root)
  "Return a live Vterm buffer rooted at ROOT."
  (require 'vterm)
  (let* ((project-name
          (file-name-nondirectory (directory-file-name root)))
         (terminal-name
          (format "*vterm:%s-%s*" project-name
                  (substring (secure-hash 'sha1 root) 0 7)))
         (buffer (get-buffer terminal-name)))
    (unless (and (buffer-live-p buffer)
                 (process-live-p (get-buffer-process buffer)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (setq buffer (get-buffer-create terminal-name))
      (with-current-buffer buffer
        (setq default-directory root)
        (let ((process-environment (lcw-vterm-process-environment)))
          (vterm-mode))
        (setq-local vertical-scroll-bar nil
                    horizontal-scroll-bar nil
                    header-line-format '((:eval (lcw-vterm-header-line))))))
    buffer))

(defun lcw-toggle-terminal-panel ()
  "Open, focus, or close a Vterm panel for the current project."
  (interactive)
  (let ((root (lcw-project-root-or-default)))
    (lcw-toggle-panel 'terminal root (lcw-project-vterm-buffer root)
                      'bottom 0.30)))

(keymap-set window-prefix-map "t" #'lcw-toggle-terminal-panel)

;; Translate ANSI colors from compilers, test runners, and package scripts.
(use-package ansi-color
  :ensure nil
  :custom
  (ansi-color-for-compilation-mode t)
  :hook (compilation-filter . ansi-color-compilation-filter))

(provide (quote init-terminal))
;;; init-terminal.el ends here
