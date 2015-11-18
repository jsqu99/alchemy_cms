# == Schema Information
#
# Table name: alchemy_contents
#
#  id           :integer          not null, primary key
#  name         :string(255)
#  essence_type :string(255)
#  essence_id   :integer
#  element_id   :integer
#  position     :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  creator_id   :integer
#  updater_id   :integer
#

module Alchemy
  class Content < ActiveRecord::Base
    include Alchemy::Logger
    include Alchemy::Touching
    include Alchemy::Hints

    # Concerns
    include Alchemy::Content::Factory

    belongs_to :essence, :polymorphic => true, :dependent => :destroy
    belongs_to :element, touch: true
    has_one :page, through: :element

    stampable stamper_class_name: Alchemy.user_class_name

    acts_as_list

    # ActsAsList scope
    def scope_condition
      # Fixes a bug with postgresql having a wrong element_id value, if element_id is nil.
      "element_id = #{element_id || 'null'} AND essence_type = '#{essence_type}'"
    end

    # Essence scopes
    scope :essence_booleans,  -> { where(essence_type: "Alchemy::EssenceBoolean") }
    scope :essence_dates,     -> { where(essence_type: "Alchemy::EssenceDate") }
    scope :essence_files,     -> { where(essence_type: "Alchemy::EssenceFile") }
    scope :essence_htmls,     -> { where(essence_type: "Alchemy::EssenceHtml") }
    scope :essence_links,     -> { where(essence_type: "Alchemy::EssenceLink") }
    scope :essence_pictures,  -> { where(essence_type: "Alchemy::EssencePicture") }
    scope :gallery_pictures,  -> { essence_pictures.where("#{self.table_name}.name LIKE 'essence_picture_%'") }
    scope :essence_richtexts, -> { where(essence_type: "Alchemy::EssenceRichtext") }
    scope :essence_selects,   -> { where(essence_type: "Alchemy::EssenceSelect") }
    scope :essence_texts,     -> { where(essence_type: "Alchemy::EssenceText") }
    scope :named,             ->(name) { where(name: name) }
    scope :available,         -> { published.not_trashed }
    scope :published,         -> { joins(:element).merge(Element.published) }
    scope :not_trashed,       -> { joins(:element).merge(Element.not_trashed) }
    scope :not_restricted,    -> { joins(:element).merge(Element.not_restricted) }

    delegate :restricted?, to: :page,    allow_nil: true
    delegate :trashed?,    to: :element, allow_nil: true
    delegate :public?,     to: :element, allow_nil: true

    class << self
      # Returns the translated label for a content name.
      #
      # Translate it in your locale yml file:
      #
      #   alchemy:
      #     content_names:
      #       foo: Bar
      #
      # Optionally you can scope your content name to an element:
      #
      #   alchemy:
      #     content_names:
      #       article:
      #         foo: Baz
      #
      def translated_label_for(content_name, element_name = nil)
        I18n.t(
          content_name,
          scope: "content_names.#{element_name}",
          default: I18n.t("content_names.#{content_name}", default: content_name.humanize)
        )
      end
    end

    # The content's view partial is dependent from its name
    #
    # == Define contents
    #
    # Contents are defined in the +config/alchemy/elements.yml+ file
    #
    #     - name: article
    #       contents:
    #       - name: headline
    #         type: EssenceText
    #
    # == Override the view
    #
    # Content partials live in +app/views/alchemy/essences+
    #
    def to_partial_path
      "alchemy/essences/#{essence_partial_name}_view"
    end

    # Settings from the elements.yml definition
    def settings
      return {} if description.blank?
      @settings ||= description.fetch('settings', {}).symbolize_keys
    end

    def siblings
      return [] if !element
      self.element.contents
    end

    # Gets the ingredient from essence
    def ingredient
      return nil if essence.nil?
      essence.ingredient
    end

    # Serialized object representation for json api
    #
    def serialize
      {
        name: name,
        value: serialized_ingredient,
        link: essence.try(:link)
      }.delete_if { |_k, v| v.blank? }
    end

    # Ingredient value from essence for json api
    #
    # If the essence responds to +serialized_ingredient+ method it takes this
    # otherwise it uses the ingredient column.
    #
    def serialized_ingredient
      essence.try(:serialized_ingredient) || ingredient
    end

    # Sets the ingredient from essence
    def ingredient=(value)
      raise EssenceMissingError if essence.nil?
      essence.ingredient = value
    end

    # Updates the essence.
    #
    # Called from +Alchemy::Element#update_contents+
    #
    # Adds errors to self.base if essence validation fails.
    #
    def update_essence(params = {})
      raise EssenceMissingError if essence.nil?

      if essence.kind_of? Alchemy::EssencePicture
        if essence.element.page.language_code == 'en'
          # find all non-english essences w/ the same name

          Alchemy::Content.where(name: essence.content.name).each do |content|
            next if content.essence == essence

            # copy this picture to every other locale...but let's guard against
            # the possible intentional "different image for this locale" done in
            # the past.  Let's assume that if the timestamps are all within
            # 45 seconds of each other that these were auto-created vs. a content
            # creator uploading a separate image
            Rails.logger.error "essence.content_#{essence.content.id}.updated_at: #{essence.content.updated_at} - content_#{content.id}.updated_at: #{content.updated_at}"

            if content.essence.picture.nil? || (essence.content.updated_at - content.updated_at).abs < 45
              Rails.logger.error "changing content b/c we think it was auto-modified"
              content.essence.update(params)
            else
              Rails.logger.error "not changing content b/c we think it was human-modified"
            end
          end
        end
      end

      if essence.update(params)
        return true
      else
        errors.add(:essence, :validation_failed)
        return false
      end
    end

    def essence_validation_failed?
      essence.errors.any?
    end

    def has_validations?
      description['validate'].present?
    end

    # Returns a string to be passed to Rails form field tags to ensure we have same params layout everywhere.
    #
    # === Example:
    #
    #   <%= text_field_tag content.form_field_name, content.ingredient %>
    #
    # === Options:
    #
    # You can pass an Essence column_name. Default is 'ingredient'
    #
    # ==== Example:
    #
    #   <%= text_field_tag content.form_field_name(:link), content.ingredient %>
    #
    def form_field_name(essence_column = 'ingredient')
      "contents[#{self.id}][#{essence_column}]"
    end

    def form_field_id(essence_column = 'ingredient')
      "contents_#{self.id}_#{essence_column}"
    end

    # Returns a string used as dom id on html elements.
    def dom_id
      return '' if essence.nil?
      "#{essence_partial_name}_#{id}"
    end

    # Returns the translated name for displaying in labels, etc.
    def name_for_label
      self.class.translated_label_for(self.name, self.element.name)
    end

    def linked?
      essence && !essence.link.blank?
    end

    # Returns true if this content should be taken for element preview.
    def preview_content?
      if description['take_me_for_preview']
        ActiveSupport::Deprecation.warn("Content definition's `take_me_for_preview` key is deprecated. Please use `as_element_title` instead.")
      end
      !!description['take_me_for_preview'] || !!description['as_element_title']
    end

    # Proxy method that returns the preview text from essence.
    #
    def preview_text(maxlength = 30)
      essence.preview_text(maxlength)
    end

    def essence_partial_name
      return '' if essence.nil?
      essence.partial_name
    end

    def normalized_essence_type
      self.class.normalize_essence_type(self.essence_type)
    end

    def has_custom_tinymce_config?
      settings[:tinymce].present?
    end

    def tinymce_class_name
      if has_custom_tinymce_config?
        "custom_tinymce #{element.name}_#{name}"
      else
        "default_tinymce"
      end
    end

    # Returns the default value from content description
    # If the value is a symbol it gets passed through i18n inside the +alchemy.default_content_texts+ scope
    def default_text(default)
      case default
      when Symbol
        I18n.t(default, scope: :default_content_texts)
      else
        default
      end
    end

  end
end
