;;; init-project.el --- Projects, files, and workspaces -*- lexical-binding: t; -*-

;; Projects use the built-in C-x p prefix. init-programming configures Eglot.
(use-package project
  :ensure nil
  :demand t
  :config
  (keymap-global-set "C-c p" project-prefix-map))

(use-package magit
  :if (locate-library "magit")
  :bind (("C-c g" . magit-status)))

(keymap-global-set "C-c c" #'compile)
(keymap-global-set "C-c t" #'project-shell)
(keymap-global-set "C-c d" #'project-dired)

;; Dired uses the other visible Dired window as the default copy/move target.
(use-package dired
  :ensure nil
  :custom
  (dired-dwim-target t)
  (dired-listing-switches "-alh"))

;; Expand directories in place with indentation instead of opening another
;; flat Dired listing. RET still visits the directory normally.
(defun lcw-dired-subtree-refresh-icons ()
  "Refresh Nerd Icons after a Dired subtree changes."
  (when (and (bound-and-true-p nerd-icons-dired-mode)
             (fboundp 'nerd-icons-dired--refresh))
    (nerd-icons-dired--refresh)))

(defun lcw-dired-subtree-line-prefix (depth)
  "Return a subtle four-column tree guide repeated for DEPTH."
  (apply #'concat
         (make-list depth (propertize "│   " 'face 'shadow))))

(use-package dired-subtree
  :if (locate-library "dired-subtree")
  :after dired
  :bind (:map dired-mode-map
              ("TAB" . dired-subtree-toggle)
              ("<tab>" . dired-subtree-toggle))
  :custom
  (dired-subtree-line-prefix #'lcw-dired-subtree-line-prefix)
  (dired-subtree-use-backgrounds nil)
  :config
  (add-hook 'dired-subtree-after-insert-hook
            #'lcw-dired-subtree-refresh-icons 90)
  (add-hook 'dired-subtree-after-remove-hook
            #'lcw-dired-subtree-refresh-icons 90))

;; Two independent, opt-in panels. They do not impose a persistent IDE layout.
(defun lcw-project-root-or-default ()
  "Return the current project root, falling back to `default-directory'."
  (if-let ((project (project-current nil)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

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

(defun lcw-toggle-dired-panel ()
  "Open, focus, or close a Dired panel for the current project."
  (interactive)
  (let ((root (lcw-project-root-or-default)))
    (lcw-toggle-panel 'dired root (dired-noselect root) 'left 0.24)))

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

(keymap-set window-prefix-map "f" #'lcw-toggle-dired-panel)
(keymap-set window-prefix-map "t" #'lcw-toggle-terminal-panel)

;; Translate ANSI colors from compilers, test runners, and package scripts.
(use-package ansi-color
  :ensure nil
  :custom
  (ansi-color-for-compilation-mode t)
  :hook (compilation-filter . ansi-color-compilation-filter))

;; Save and restore workspaces and buffers between interactive sessions.
(defun lcw-desktop-ignore-tab-line (&rest _buffer-locals)
  "Keep Tab Line disabled when restoring an older desktop session."
  (tab-line-mode -1))

(defconst lcw-desktop-directory (expand-file-name "state/desktop/" user-emacs-directory)
  "Directory holding the session saved by `desktop'.")

(defun lcw-restore-desktop ()
  "Restore the session saved by the previous Emacs.
Startup deliberately shows the dashboard instead, so this is the explicit way
back into the last session."
  (interactive)
  (setq desktop-dirname lcw-desktop-directory)
  (unless (desktop-read lcw-desktop-directory)
    (user-error "No desktop file in %s" (abbreviate-file-name lcw-desktop-directory)))
  (lcw-desktop-enable-saving))

(defun lcw-desktop-enable-saving (&rest _)
  "Start saving the session once the session is actually in use.
`desktop' restores from its own `after-init-hook' entry and rewrites the file
on exit whenever `desktop-save-mode' is on.  Leaving the mode off until the
session is restored (or a file is visited) keeps quitting straight from the
dashboard from overwriting the previous session with an empty one."
  (unless desktop-save-mode
    (setq desktop-dirname lcw-desktop-directory)
    (desktop-save-mode 1)))

(use-package desktop
  :ensure nil
  :custom
  (desktop-path (list lcw-desktop-directory))
  (desktop-base-file-name "session")
  (desktop-base-lock-name "session.lock")
  (desktop-save t)
  (desktop-restore-eager 5)
  (desktop-restore-frames nil)
  (desktop-load-locked-desktop 'check-pid)
  :config
  ;; Tab Line is deliberately disabled in init-ui. Do not let a desktop file
  ;; restore an older buffer-local tab-line-mode state after UI setup.
  (add-to-list 'desktop-minor-mode-table '(tab-line-mode nil))
  (add-to-list 'desktop-minor-mode-handlers
               '(tab-line-mode . lcw-desktop-ignore-tab-line))
  (add-hook 'desktop-after-read-hook #'lcw-disable-tab-line-in-all-buffers)
  ;; See `lcw-desktop-enable-saving': the mode stays off during startup so that
  ;; `after-init-hook' does not restore the previous session, and it is switched
  ;; on again as soon as that session is in use.
  (unless noninteractive
    (setq desktop-dirname lcw-desktop-directory)
    (add-hook 'find-file-hook #'lcw-desktop-enable-saving 90)
    (add-hook 'dired-mode-hook #'lcw-desktop-enable-saving 90)))

(provide 'init-project)
;;; init-project.el ends here
