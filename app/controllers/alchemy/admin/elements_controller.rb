require 'localeapp'
module Alchemy
  module Admin
    class ElementsController < Alchemy::Admin::BaseController
      before_action :load_element, only: [:update, :trash, :fold]
      authorize_resource class: Alchemy::Element

      def index
        @page = Page.find(params[:page_id])
        @cells = @page.cells
        if @cells.blank?
          @elements = @page.elements.not_trashed
        else
          @elements = @page.elements_grouped_by_cells
        end
      end

      def list
        @page_id = params[:page_id]
        if @page_id.blank? && !params[:page_urlname].blank?
          @page_id = Language.current.pages.find_by(urlname: params[:page_urlname]).id
        end
        @elements = Element.published.where(page_id: @page_id)
      end

      def new
        @page = Page.find_by_id(params[:page_id])
        @element = @page.elements.build
        @elements = @page.available_element_definitions
        @clipboard = get_clipboard('elements')
        @clipboard_items = Element.all_from_clipboard_for_page(@clipboard, @page)
      end

      # Creates a element as discribed in config/alchemy/elements.yml on page via AJAX.
      def create
        @page = Page.find(params[:element][:page_id])
        Element.transaction do
          if @paste_from_clipboard = params[:paste_from_clipboard].present?
            @element = paste_element_from_clipboard
            @cell = @element.cell
          else
            @element = Element.new_from_scratch(params[:element])
            if @page.can_have_cells?
              @cell = find_or_create_cell
              @element.cell = @cell
            end
            @element.save
          end
          if @page.definition['insert_elements_at'] == 'top'
            @insert_at_top = true
            @element.move_to_top
          end
        end
        @cell_name = @cell.nil? ? "for_other_elements" : @cell.name
        if @element.valid?

          Rails.logger.error "[ALCHEMY_LOCALE] updating contents for element in elements_controller#create: #{@element}"
          update_translations(@element) if @element.page.language.language_code == 'en'

          render :create
        else
          @element.page = @page
          @elements = @page.available_element_definitions
          @clipboard = get_clipboard('elements')
          @clipboard_items = Element.all_from_clipboard_for_page(@clipboard, @page)
          render :new
        end
      end

      # Updates the element.
      #
      # And update all contents in the elements by calling update_contents.
      #
      def update
        if @element.update_contents(contents_params)
          @page = @element.page
          @element_validated = @element.update_attributes!(element_params)

          Rails.logger.error "[ALCHEMY_LOCALE] updating contents for element in elements_controller#update: #{@element}"
          update_translations(@element) if @element.page.language.language_code == 'en'
          update_skip_translate(params[:skip_translate]) unless params[:skip_translate].nil?
        else
          @element_validated = false
          @notice = _t('Validation failed')
          @error_message = "<h2>#{@notice}</h2><p>#{_t(:content_validations_headline)}</p>".html_safe
        end
      end

      # Trashes the Element instead of deleting it.
      def trash
        @page = @element.page
        @element.trash!
      end

      def order
        @trashed_element_ids = Element.trashed.where(id: params[:element_ids]).pluck(:id)
        Element.transaction do
          params[:element_ids].each_with_index do |element_id, idx|
            # Ensure to set page_id and cell_id to the current page and
            # cell because of trashed elements could still have old values
            Element.where(id: element_id).update_all(
              page_id: params[:page_id],
              cell_id: params[:cell_id],
              position: idx + 1
            )
          end
        end
      end

      def fold
        @page = @element.page
        @element.folded = !@element.folded
        @element.save
      end

      private
      def update_translations(element)
        locale = element.page.language.language_code

        # do _not_ update foreign languages from alchemy
        return unless locale == 'en'

        element.essences.each do |essence|
          next unless [Alchemy::EssenceText,Alchemy::EssenceRichtext,Alchemy::EssenceHtml].include? essence.class
          next if essence.content.skip_translate
          position = essence.element.position
          key = "#{essence.content.name}_pos_#{position}"

          description = essence.body

          Rails.logger.info "[ALCHEMY_LOCALE] locale/key/value added to localeapp queue: #{locale}/#{key}/#{description}"

          Localeapp.missing_translations.add(locale, "#{Alchemy::Translations::TRANSLATION_PREFIX}.#{key}", description)
        end

        Rails.logger.info "[ALCHEMY_LOCALE] posting missing translations to locale"

        Localeapp.sender.post_missing_translations
        Alchemy::TranslationSentEmail.new.perform(Localeapp.missing_translations.to_send.to_json)
      end

      def update_skip_translate(skip_translate_hash)
        skip_translate_hash.each do |content_id, value|
          content = Alchemy::Content.find content_id
          content.update(skip_translate: value)
        end
      end

      def load_element
        @element = Element.find(params[:id])
      end

      # Returns the cell for element name in params.
      # Creates the cell if necessary.
      def find_or_create_cell
        if @paste_from_clipboard
          element_with_cell_name = params[:paste_from_clipboard]
        else
          element_with_cell_name = params[:element][:name]
        end
        return nil if element_with_cell_name.blank?
        return nil unless element_with_cell_name.include?('#')
        cell_name = element_with_cell_name.split('#').last
        cell_definition = Cell.definition_for(cell_name)
        if cell_definition.blank?
          raise CellDefinitionError, "Cell definition not found for #{cell_name}"
        end
        @page.cells.find_or_create_by(name: cell_definition['name'])
      end

      def element_from_clipboard
        @element_from_clipboard ||= begin
          @clipboard = get_clipboard('elements')
          @clipboard.detect { |item| item['id'].to_i == params[:paste_from_clipboard].to_i }
        end
      end

      def paste_element_from_clipboard
        @source_element = Element.find(element_from_clipboard['id'])
        new_attributes = {:page_id => @page.id}
        if @page.can_have_cells?
          new_attributes = new_attributes.merge({:cell_id => find_or_create_cell.try(:id)})
        end
        element = Element.copy(@source_element, new_attributes)
        if element_from_clipboard['action'] == 'cut'
          cut_element
        end
        element
      end

      def cut_element
        @cutted_element_id = @source_element.id
        @clipboard.delete_if { |item| item['id'] == @source_element.id.to_s }
        @source_element.destroy
      end

      def contents_params
        params.fetch(:contents, {}).permit!
      end

      def element_params
        params.require(:element).permit(:public, :tag_list)
      end

    end
  end
end
