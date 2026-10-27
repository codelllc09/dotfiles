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

;; A full-frame, multi-pane file browser with live previews lives on the
;; classic Dired key.  C-x C-f keeps the minibuffer completion workflow; a
;; prefix argument prompts for the directory first, like classic C-x d.
(defun lcw-browse-files (prompt-for-dir)
  "Browse files visually, or PROMPT-FOR-DIR like classic `dired'.
Interactively, PROMPT-FOR-DIR is the prefix argument."
  (interactive "P")
  (if prompt-for-dir
      (call-interactively #'dired)
    (dirvish default-directory)))

(defun lcw-dirvish-disable-legacy-icons ()
  "Let Dirvish be the sole icon renderer in its Dired buffer."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (nerd-icons-dired-mode -1)))

;; Load the struct accessors before defining commands that update session
;; fields.  The package itself remains conditional for fresh installations.
(when (locate-library "dirvish")
  (require 'dirvish)
  ;; NonGNU ELPA 2.3 keeps dirvish-side in the extensions subdirectory
  ;; without autoloads.  The use-package form below adds that path too,
  ;; but only after this block has run, so extend `load-path' here first.
  (when-let* ((library (locate-library "dirvish"))
              (extensions (expand-file-name "extensions"
                                            (file-name-directory library))))
    (when (file-directory-p extensions)
      (add-to-list 'load-path extensions)))
  ;; The side-bar extension ships without autoloads entries, so `M-x
  ;; dirvish-side' stays invisible until it is loaded here explicitly.
  ;; `dirvish-side-follow-mode' makes the tree reveal the current file,
  ;; like the VSCode explorer sidebar.
  (require 'dirvish-side)
  (dirvish-side-follow-mode 1))

(defun lcw-dirvish-listing-shows-hidden-p (switches)
  "Return non-nil when ls SWITCHES include hidden files."
  (seq-some
   (lambda (switch)
     (or (member switch '("--all" "--almost-all"))
         (and (string-match-p "\\`-[^-]" switch)
              (string-match-p "[aA]" switch))))
   (split-string switches nil t)))

(defun lcw-dirvish-set-hidden-switch (switches show)
  "Return ls SWITCHES adjusted to SHOW or hide dotfiles."
  (let ((parts (split-string switches nil t)))
    (if show
        (if (lcw-dirvish-listing-shows-hidden-p switches)
            switches
          (mapconcat #'identity (cons "-A" parts) " "))
      (mapconcat
       #'identity
       (delq
        nil
        (mapcar
         (lambda (switch)
           (cond
            ((member switch '("--all" "--almost-all")) nil)
            ((string-match-p "\\`-[^-]+\\'" switch)
             (let ((trimmed
                    (replace-regexp-in-string "[aA]" "" switch)))
               (unless (equal trimmed "-") trimmed)))
            (t switch)))
         parts))
       " "))))

(defun lcw-dirvish-sync-listing-switches ()
  "Keep previews consistent with the current Dirvish session."
  (when-let ((session (dirvish-curr)))
    (setq-local dired-listing-switches (dv-ls-switches session))))

(defun lcw-dirvish-toggle-hidden-files ()
  "Toggle dotfiles throughout the current Dirvish session."
  (interactive)
  (let* ((session (or (dirvish-curr)
                      (user-error "Not in a Dirvish session")))
         (show (not (lcw-dirvish-listing-shows-hidden-p
                     (dv-ls-switches session))))
         (switches
          (lcw-dirvish-set-hidden-switch (dv-ls-switches session) show))
         (index-buffer (cdr (dv-index session)))
         (root-window (dv-root-window session)))
    (setf (dv-ls-switches session) switches)
    (dolist (root (dv-roots session))
      (when (buffer-live-p (cdr root))
        (with-current-buffer (cdr root)
          (setq-local dired-listing-switches switches)
          (dired-sort-other switches))))
    ;; Parent and preview panes cache directory contents separately.
    (clrhash (dv-parent-hash session))
    (clrhash (dv-preview-hash session))
    (when (and (buffer-live-p index-buffer) (window-live-p root-window))
      (with-selected-window root-window
        (switch-to-buffer index-buffer)
        (dirvish--build-layout session)
        (dirvish--redisplay)))
    (message "Hidden files %s" (if show "shown" "hidden"))))

(use-package dirvish
  :if (locate-library "dirvish")
  :commands dirvish
  :init
  ;; NonGNU ELPA 2.3 keeps optional features in this subdirectory without
  ;; adding it to `load-path'; newer releases do so during installation.
  (when-let* ((library (locate-library "dirvish"))
              (extensions
               (expand-file-name "extensions" (file-name-directory library))))
    (when (file-directory-p extensions)
      (add-to-list 'load-path extensions)))
  (dirvish-override-dired-mode 1)
  :bind (("C-x d" . lcw-browse-files)
         :map dirvish-mode-map
         ("h" . dired-up-directory)
         ("j" . dired-next-line)
         ("k" . dired-previous-line)
         ("l" . dired-find-file)
         ("." . lcw-dirvish-toggle-hidden-files)
         ("?" . dirvish-dispatch)
         ("TAB" . dirvish-subtree-toggle)
         ("<tab>" . dirvish-subtree-toggle)
         ("M-f" . dirvish-history-go-forward)
         ("M-b" . dirvish-history-go-backward))
  :custom
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse file-time file-size))
  ;; `dirvish-side-attributes' defaults to a snapshot of
  ;; `dirvish-attributes' taken when dirvish-side loads, which happens
  ;; before this :custom applies.  Set it explicitly, and keep only
  ;; attributes that fit the narrow tree (no time/size/collapse).
  (dirvish-side-attributes '(vc-state subtree-state nerd-icons))
  (dirvish-use-header-line 'global)
  (dirvish-mode-line-bar-image-width 0)
  :config
  (require 'dirvish-history)
  (add-hook 'dirvish-setup-hook #'lcw-dirvish-disable-legacy-icons)
  (add-hook 'dirvish-setup-hook #'lcw-dirvish-sync-listing-switches))

;; dired-subtree expanded subdirectories in place inside plain Dired
;; buffers; it served the retired left Dired panel.  Dirvish ships its own
;; subtree (TAB = dirvish-subtree-toggle), so this block stays disabled.
;; Uncomment everything below to restore.  -- retired 2026-10
;;
;; (defun lcw-dired-subtree-refresh-icons ()
;;   "Refresh Nerd Icons after a Dired subtree changes."
;;   (when (and (bound-and-true-p nerd-icons-dired-mode)
;;              (fboundp 'nerd-icons-dired--refresh))
;;     (nerd-icons-dired--refresh)))
;;
;; (defun lcw-dired-subtree-line-prefix (depth)
;;   "Return a subtle four-column tree guide repeated for DEPTH."
;;   (apply #'concat
;;          (make-list depth (propertize "│   " 'face 'shadow))))
;;
;; (use-package dired-subtree
;;   :if (locate-library "dired-subtree")
;;   :after dired
;;   :bind (:map dired-mode-map
;;               ("TAB" . dired-subtree-toggle)
;;               ("<tab>" . dired-subtree-toggle))
;;   :custom
;;   (dired-subtree-line-prefix #'lcw-dired-subtree-line-prefix)
;;   (dired-subtree-use-backgrounds nil)
;;   :config
;;   (add-hook 'dired-subtree-after-insert-hook
;;             #'lcw-dired-subtree-refresh-icons 90)
;;   (add-hook 'dired-subtree-after-remove-hook
;;             #'lcw-dired-subtree-refresh-icons 90))

;; Opt-in side panels that impose no persistent IDE layout.  File browsing
;; moved to Dirvish on C-x d (see above); the left Dired panel was retired
;; with dired-subtree in 2026-10.
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

(keymap-set window-prefix-map "f" #'dirvish-side)
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
