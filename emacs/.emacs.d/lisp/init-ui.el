;;; init-ui.el --- Frames, tabs, themes, fonts, and icons -*- lexical-binding: t; -*-

(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))
(when (fboundp 'horizontal-scroll-bar-mode)
  (horizontal-scroll-bar-mode -1))
(column-number-mode 1)

;; Keep the mode line informational only.  The default format attaches local
;; mouse maps to the buffer name, position, major mode, and minor modes.
(defvar lcw-mode-line--display-format nil
  "Left side of the compact, noninteractive mode line.")

(defvar lcw-mode-line--right-format nil
  "Right side of the compact, noninteractive mode line.")

;; Keep the header line focused on file identity.  Position lives on the left
;; of the mode line; file state and compact metadata use the remaining space.
(setq lcw-mode-line--display-format
      '(" "
        (:eval (lcw-mode-line-file-state))
        (:eval (lcw-mode-line-separator))
        "%p"
        (:eval (lcw-mode-line-separator))
        "Ln %l · Col %c"))

(setq lcw-mode-line--right-format
      '(
        (:eval (lcw-mode-line-file-metadata))
        " "
        mode-line-end-spaces))

(defvar lcw-mode-line-text-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'ignore)
    (define-key map [mode-line mouse-2] #'ignore)
    (define-key map [mode-line mouse-3] #'ignore)
    (define-key map [mode-line down-mouse-1] #'mouse-drag-mode-line)
    map)
  "Mouse map that makes mode-line text inert while retaining drag resize.")

(defun lcw-mode-line--escape-percent (text)
  "Double percent signs in TEXT while preserving its text properties."
  (let ((position 0))
    (while (setq position (string-match "%" text position))
      (setq text (concat (substring text 0 position)
                         (substring text position (1+ position))
                         (substring text position))
            position (+ position 2)))
    text))

(defun lcw-mode-line-noninteractive (&optional format)
  "Render FORMAT with clickable properties removed.
FORMAT defaults to the left-side `lcw-mode-line--display-format'."
  ;; The returned string is parsed once more by the outer `:eval', so protect
  ;; literal percent signs produced by `%p' (for example, "31%").
  (let ((text (lcw-mode-line--escape-percent
               (format-mode-line
                (or format lcw-mode-line--display-format)))))
    (remove-list-of-text-properties
     0 (length text) '(local-map keymap mouse-face help-echo) text)
    (add-text-properties
     0 (length text) `(local-map ,lcw-mode-line-text-map) text)
    text))

(setq-default mode-line-format
              '((:eval
                 (lcw-mode-line-noninteractive
                  lcw-mode-line--display-format))
                mode-line-format-right-align
                (:eval
                 (lcw-mode-line-noninteractive
                  lcw-mode-line--right-format))))
(force-mode-line-update t)

(defun lcw-ui-file-buffer-p ()
  "Return non-nil when the current buffer represents a visited file.
Indirect buffers inherit the file identity of their base buffer."
  (or buffer-file-name
      (when-let* ((base (buffer-base-buffer)))
        (buffer-local-value 'buffer-file-name base))))

(defun lcw-apply-mode-line-policy ()
  "Show the mode line only for document and source-code file buffers."
  (setq-local mode-line-format
              (when (lcw-ui-file-buffer-p)
                (default-value 'mode-line-format)))
  (force-mode-line-update))

;; Tool buffers (Agent Shell, Dired, Magit, Help, Messages, compilation,
;; terminals, warnings, completion lists, and similar) do not visit a file and
;; therefore do not need file state or position metadata.  Re-evaluate when a
;; buffer changes mode or gains a visited file name.
(add-hook 'after-change-major-mode-hook #'lcw-apply-mode-line-policy 100)
(add-hook 'find-file-hook #'lcw-apply-mode-line-policy 100)
(add-hook 'after-set-visited-file-name-hook #'lcw-apply-mode-line-policy 100)
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (unless (minibufferp buffer)
      (lcw-apply-mode-line-policy))))

(defun lcw-hide-noisy-mode-line-lighters ()
  "Hide redundant minor-mode labels without disabling their features."
  (dolist (mode '(which-key-mode
                  eldoc-mode))
    (when-let* ((entry (assq mode minor-mode-alist)))
      (setcdr entry '(nil)))))

(lcw-hide-noisy-mode-line-lighters)
(with-eval-after-load 'which-key
  (lcw-hide-noisy-mode-line-lighters))
(with-eval-after-load 'eldoc
  (lcw-hide-noisy-mode-line-lighters))

(defun lcw-hide-markdown-mode-name ()
  "Hide the redundant GFM major-mode label in Markdown buffers."
  (when (derived-mode-p 'markdown-mode)
    (setq-local mode-name nil)))

(add-hook 'gfm-mode-hook #'lcw-hide-markdown-mode-name 90)
;; Apply the same display change when this file is reloaded with Markdown
;; buffers already open.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (lcw-hide-markdown-mode-name)))

;; Restore the normal background actions in sessions that loaded the earlier
;; version of this setting.  The text-specific map above still absorbs clicks.
(keymap-global-set "<mode-line> <down-mouse-1>" #'mouse-drag-mode-line)
(keymap-global-set "<mode-line> <mouse-1>" #'mouse-select-window)
(keymap-global-set "<mode-line> <mouse-2>" #'mouse-delete-other-windows)
(keymap-global-set "<mode-line> <mouse-3>" #'mouse-delete-window)

;; Give the frame content some breathing room and keep split windows distinct.
;; The default applies to future frames; set-frame-parameter updates this one.
(add-to-list 'default-frame-alist '(vertical-scroll-bars . nil))
(add-to-list 'default-frame-alist '(horizontal-scroll-bars . nil))
(add-to-list 'default-frame-alist '(internal-border-width . 15))
(set-frame-parameter nil 'internal-border-width 15)
(setq window-divider-default-right-width 1
      window-divider-default-bottom-width 2)
(window-divider-mode 1)

(defface lcw-terminal-header-label
  '((t (:inherit header-line :foreground "#89b4fa" :weight bold)))
  "Face for the terminal panel label and working directory.")

(defface lcw-terminal-header-hint
  '((t (:inherit header-line :foreground "#6c7086")))
  "Face for the terminal panel's quiet key hint.")

(defface lcw-file-header-path
  '((t (:inherit header-line :foreground "#cdd6f4" :weight semi-bold)))
  "Face for the file location in the header line.")

(defface lcw-mode-line-separator-face
  '((t (:foreground "#45475a")))
  "Face for quiet separators in the mode line.")

(defface lcw-mode-line-file-meta
  '((t (:foreground "#6c7086")))
  "Face for coding and size metadata in the mode line.")

(defface lcw-mode-line-modified
  '((t (:foreground "#f38ba8" :weight bold)))
  "Face for the mode-line modified marker.")

(defface lcw-mode-line-read-only
  '((t (:foreground "#fab387" :weight bold)))
  "Face for the mode-line file read-only marker.")

(defface lcw-mode-line-wrap
  '((t (:foreground "#89b4fa")))
  "Face for the visual-line-mode marker.")

(defun lcw-copy-current-file-path ()
  "Copy the current buffer's complete local or TRAMP file path."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer does not visit a file"))
  (kill-new buffer-file-name)
  (message "Copied: %s" buffer-file-name))

(defun lcw-header-copy-file-path (event)
  "Copy the file path belonging to the header line clicked by EVENT."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (with-selected-window window
        (lcw-copy-current-file-path)))))

(defvar lcw-file-header-path-map
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line down-mouse-1] #'ignore)
    (define-key map [header-line mouse-1] #'lcw-header-copy-file-path)
    map)
  "Mouse map for copying the path displayed in the header line.")

(defun lcw-file-header-path-label ()
  "Return a readable local or TRAMP location for the current buffer."
  (if-let* ((file buffer-file-name))
      (let* ((method (file-remote-p file 'method))
             (label
              (if method
                  (let ((user (file-remote-p file 'user))
                        (host (file-remote-p file 'host))
                        (localname (file-remote-p file 'localname)))
                    (format "%s %s%s › %s"
                            (upcase method)
                            (if user (concat user "@") "")
                            (or host "remote")
                            localname))
                (abbreviate-file-name file))))
        (propertize (lcw-mode-line--escape-percent label)
                    'face 'lcw-file-header-path
                    'help-echo "Click to copy path"
                    'mouse-face 'mode-line-highlight
                    'local-map lcw-file-header-path-map))
    (propertize (buffer-name) 'face 'lcw-file-header-path)))

(defun lcw-file-header-coding-label ()
  "Return a compact encoding and end-of-line label for this buffer."
  (let* ((coding buffer-file-coding-system)
         (base (and coding (coding-system-base coding)))
         (eol (and coding (coding-system-eol-type coding))))
    (when base
      (format "%s %s"
              (upcase (symbol-name base))
              (pcase eol
                (0 "LF")
                (1 "CRLF")
                (2 "CR")
                (_ "EOL?"))))))

(defun lcw-file-header-disk-read-only-p ()
  "Return non-nil when the visited file itself cannot be written or created."
  (and buffer-file-name
       (file-exists-p buffer-file-name)
       (not (file-writable-p buffer-file-name))))

(defun lcw-ui--join-items (items separator)
  "Join propertized display ITEMS using SEPARATOR."
  (let ((result nil))
    (dolist (item (delq nil items))
      (when result
        (setq result (concat result separator)))
      (setq result (concat result item)))
    (or result "")))

(defun lcw-mode-line-separator ()
  "Return a quiet, consistently padded mode-line separator."
  (propertize "  │  " 'face 'lcw-mode-line-separator-face))

(defun lcw-mode-line-file-state ()
  "Return readable modification and real file read-only indicators."
  (let ((state
         (lcw-ui--join-items
          (list
           (when (buffer-modified-p)
             (propertize "MOD" 'face 'lcw-mode-line-modified))
           (when (lcw-file-header-disk-read-only-p)
             (propertize "RO" 'face 'lcw-mode-line-read-only)))
          " ")))
    (if (string-empty-p state)
        ""
      (concat (lcw-mode-line-separator) state))))

(defun lcw-mode-line-file-metadata ()
  "Return coding, buffer size, and wrapping information for the mode line."
  (let ((metadata
         (lcw-ui--join-items
          (list
           (when-let* ((coding (lcw-file-header-coding-label)))
             (propertize coding 'face 'lcw-mode-line-file-meta))
           (propertize
            (file-size-human-readable (buffer-size) 'iec " " "B")
            'face 'lcw-mode-line-file-meta)
           (when (bound-and-true-p visual-line-mode)
             (propertize "Wrap" 'face 'lcw-mode-line-wrap)))
          (lcw-mode-line-separator))))
    metadata))

(defun lcw-file-header-line ()
  "Build the clickable file-location header line for the current buffer."
  (list " " (lcw-file-header-path-label) " "))

;; A tab-bar tab is a workspace/window layout. Its icon follows the buffer that
;; represents the workspace, like the program icon in the WezTerm tab title.
(defun lcw-tab-bar-tab-buffer (tab)
  "Return the representative live buffer for TAB."
  (if (eq (car tab) 'current-tab)
      (window-buffer (selected-window))
    (let ((point-marker (alist-get 'wc-point tab)))
      (or (and (markerp point-marker) (marker-buffer point-marker))
          (seq-find #'buffer-live-p (alist-get 'wc-bl tab))
          (get-buffer (alist-get 'name tab))))))

(defun lcw-tab-bar-tab-name-format-icon (name tab _index)
  "Prefix TAB's NAME with an icon for its representative buffer."
  (let* ((buffer (lcw-tab-bar-tab-buffer tab))
         (icon (and buffer
                    (fboundp 'nerd-icons-icon-for-buffer)
                    (with-current-buffer buffer
                      (nerd-icons-icon-for-buffer)))))
    ;; Let the active/inactive tab face color the icon together with the name.
    (concat (if (and (stringp icon) (not (string-empty-p icon)))
                (substring-no-properties icon)
              "◇")
            " " name)))

(defun lcw-tab-bar-tab-name-format-padding (name _tab _index)
  "Add compact horizontal breathing room around a tab NAME."
  (concat " " name " "))

(defun lcw-tab-bar-tab-name-format-status (name tab _index)
  "Prefix NAME with a clear active or inactive workspace marker."
  (concat (if (eq (car tab) 'current-tab) "● " "· ") name))

(defun lcw-apply-ui-faces ()
  "Style tabs, contextual status lines, and window boundaries."
  (set-face-attribute 'tab-bar nil
                      :inherit 'default
                      :background "#181825"
                      :foreground "#6c7086"
                      :box nil)
  (set-face-attribute 'tab-bar-tab nil
                      :inherit 'tab-bar
                      :background "#313244"
                      :foreground "#cdd6f4"
                      :weight 'bold
                      :overline "#89b4fa"
                      :box '(:line-width (6 . 3) :color "#313244"))
  (set-face-attribute 'tab-bar-tab-inactive nil
                      :inherit 'tab-bar
                      :background "#181825"
                      :foreground "#6c7086"
                      :weight 'normal
                      :overline nil
                      :box '(:line-width (6 . 3) :color "#181825"))
  (set-face-attribute 'header-line nil
                      :inherit 'mode-line-inactive
                      :background "#181825"
                      :foreground "#a6adc8"
                      :box nil)
  (set-face-attribute 'lcw-terminal-header-label nil
                      :inherit 'header-line
                      :foreground "#89b4fa"
                      :weight 'bold)
  (set-face-attribute 'lcw-terminal-header-hint nil
                      :inherit 'header-line
                      :foreground "#6c7086")
  (set-face-attribute 'lcw-file-header-path nil
                      :inherit 'header-line
                      :foreground "#cdd6f4"
                      :weight 'semi-bold)
  (set-face-attribute 'lcw-mode-line-separator-face nil
                      :inherit nil
                      :foreground "#45475a")
  (set-face-attribute 'lcw-mode-line-file-meta nil
                      :inherit nil
                      :foreground "#6c7086")
  (set-face-attribute 'lcw-mode-line-modified nil
                      :inherit nil
                      :foreground "#f38ba8"
                      :weight 'bold)
  (set-face-attribute 'lcw-mode-line-read-only nil
                      :inherit nil
                      :foreground "#fab387"
                      :weight 'bold)
  (set-face-attribute 'lcw-mode-line-wrap nil
                      :inherit nil
                      :foreground "#89b4fa")
  (dolist (face '(window-divider
                  window-divider-first-pixel
                  window-divider-last-pixel))
    (set-face-attribute face nil :foreground "#45475a")))

;; Keep the bar hidden until a second workspace exists. Unlike the default,
;; compact tabs follow their title width instead of filling the entire frame.
(use-package tab-bar
  :ensure nil
  :custom
  (tab-bar-show 1)
  (tab-bar-auto-width nil)
  (tab-bar-tab-hints t)
  (tab-bar-separator "")
  (tab-bar-close-button-show nil)
  (tab-bar-tab-name-format-functions
   '(lcw-tab-bar-tab-name-format-icon
     tab-bar-tab-name-format-hints
     lcw-tab-bar-tab-name-format-status
     tab-bar-tab-name-format-close-button
     lcw-tab-bar-tab-name-format-padding
     tab-bar-tab-name-format-face))
  :config
  (lcw-apply-ui-faces)
  (tab-bar-mode 1)
  (tab-bar-history-mode 1))

;; Buffers are selected through consult-buffer, so a persistent tab line would
;; duplicate that workflow and consume a row in every window.
(defun lcw-disable-tab-line-in-all-buffers ()
  "Disable Tab Line globally and in buffers restored from an old desktop."
  (global-tab-line-mode -1)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when tab-line-mode
        (tab-line-mode -1)))))

(use-package tab-line
  :ensure nil
  :config
  (lcw-disable-tab-line-in-all-buffers))

;; Use the native header line for the clickable file location.  Status and
;; metadata stay in the display-only bottom mode line.
(setq-default header-line-format
              '((:eval (lcw-file-header-line))))

;; Curated dark-theme lineup. C-c T previews themes through consult-theme;
;; M-x lcw-load-theme switches directly.
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes/github-dark/" user-emacs-directory))

(use-package doom-themes
  :if (locate-library "doom-themes")
  :config
  (doom-themes-org-config))

(use-package catppuccin-theme
  :if (locate-library "catppuccin-theme")
  :custom
  (catppuccin-flavor 'mocha))

(defvar lcw-default-theme 'catppuccin
  "Theme loaded at startup.
Popular picks: catppuccin, doom-one, doom-dracula, modus-vivendi,
nord, gruvbox, solarized-dark, github-dark.")

(defun lcw-load-theme (theme)
  "Disable enabled themes, then load THEME without confirmation."
  (interactive
   (list (read (completing-read "Load theme: "
                                (mapcar #'symbol-name
                                        (custom-available-themes))))))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (lcw-apply-ui-faces))

(cond ((memq lcw-default-theme (custom-available-themes))
       (lcw-load-theme lcw-default-theme))
      ((memq 'github-dark (custom-available-themes))
       (lcw-load-theme 'github-dark)))

;; Use an explicitly monospaced font in graphical frames, including daemon clients.
(defvar lcw-code-font-family "Maple Mono NF CN"
  "Monospaced font used for source code.")

(defun lcw-apply-code-font (&optional frame)
  "Apply the code font to graphical FRAME without changing its font size."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (when (find-font (font-spec :family lcw-code-font-family) frame)
        (set-face-attribute 'default frame :family lcw-code-font-family)
        (set-face-attribute 'fixed-pitch frame :family lcw-code-font-family)
        (dolist (script '(han kana cjk-misc bopomofo))
          (set-fontset-font t script
                            (font-spec :family lcw-code-font-family)
                            frame))))))

(add-hook 'after-make-frame-functions #'lcw-apply-code-font)
(lcw-apply-code-font)

;; nerd-icons reads Nerd Font v3 codepoints directly from Maple Mono NF CN.
(use-package nerd-icons
  :if (locate-library "nerd-icons")
  :custom
  (nerd-icons-font-family lcw-code-font-family))

(use-package nerd-icons-dired
  :if (locate-library "nerd-icons-dired")
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-corfu
  :if (locate-library "nerd-icons-corfu")
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-completion
  :if (locate-library "nerd-icons-completion")
  :after marginalia
  :config
  (nerd-icons-completion-mode))

(provide 'init-ui)
;;; init-ui.el ends here
