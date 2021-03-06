$.extend Alchemy,

  # Opens an image in a dialog
  # Used by the picture library
  zoomImage: (url, title, width, height) ->
    Alchemy.openDialog url,
      size: "#{width}x#{height}"
      title: title
      padding: false
      overflow: 'hidden'
      ready: (dialog) ->
        Alchemy.ImageLoader dialog,
          color: '#000'

  # Trash window methods
  TrashWindow:

    # Opens the trash window
    open: (page_id, title) ->
      url = Alchemy.routes.admin_trash_path(page_id)
      @current = new Alchemy.Dialog url,
        title: title,
        size: '380x460',
        modal: false
      @current.open()
      return

    # Refreshes the trash window
    refresh: ->
      @current.reload() if @current
      return

    # Update the trash window icon
    updateIcon: ->
      return unless @current?
      $icon = $("#element_trash_button .icon")
      # Is the trash window open?
      if $("#trash_items div.element-editor").not(".dragged").length is 0
        $icon.removeClass("full")
      else
        $icon.addClass("full")
      return
