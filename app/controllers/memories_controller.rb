class MemoriesController < ApplicationController
  before_action :set_space
  before_action :set_memory, only: [ :show, :edit, :update, :destroy, :archive, :activate, :versions, :version, :restore_version ]

  # GET /spaces/:space_id/memories
  def index
    @memories = @space.memories
                       .active
                       .ordered
                       .by_type(params[:type])
                       .search(params[:q])

    @memory_types = Memory::MEMORY_TYPES
    @selected_type = params[:type]
    @search_query = params[:q]
  end

  # GET /spaces/:space_id/memories/:id
  def show
  end

  # GET /spaces/:space_id/memories/new
  def new
    @memory = @space.memories.new(
      memory_type: params[:type] || "knowledge",
      status: "active",
      position: (@space.memories.maximum(:position) || 0) + 1
    )
  end

  # GET /spaces/:space_id/memories/:id/edit
  def edit
  end

  # POST /spaces/:space_id/memories
  def create
    @memory = @space.memories.new(memory_params)
    @memory.account = Current.account
    @memory.created_by = Current.user
    @memory.updated_by = Current.user

    if @memory.save
      redirect_to space_memory_path(@space, @memory), notice: "Memory was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /spaces/:space_id/memories/:id
  def update
    @memory.updated_by = Current.user

    # Track what changed for the version
    changes = []
    changes << "title" if memory_params[:title].present? && memory_params[:title] != @memory.title
    changes << "content" if memory_params[:content].present? && memory_params[:content] != @memory.content
    changes << "type" if memory_params[:memory_type].present? && memory_params[:memory_type] != @memory.memory_type

    if @memory.update(memory_params)
      # Create a version if content actually changed
      if changes.any?
        @memory.create_version!(
          created_by: Current.user,
          change_reason: "Manual update by user (#{changes.join(', ')})"
        )
      end
      redirect_to space_memory_path(@space, @memory), notice: "Memory was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /spaces/:space_id/memories/:id
  def destroy
    @memory.destroy
    redirect_to space_memories_path(@space), notice: "Memory was successfully deleted."
  end

  # POST /spaces/:space_id/memories/:id/archive
  def archive
    @memory.archive!(Current.user)
    redirect_to space_memory_path(@space, @memory), notice: "Memory was archived."
  end

  # POST /spaces/:space_id/memories/:id/activate
  def activate
    @memory.activate!(Current.user)
    redirect_to space_memory_path(@space, @memory), notice: "Memory was activated."
  end

  # GET /spaces/:space_id/memories/search
  def search
    @memories = @space.memories
                       .active
                       .search(params[:q])
                       .recent
                       .limit(20)

    @search_query = params[:q]
  end

  # GET /spaces/:space_id/memories/export
  def export
    @memories = @space.memories.active.ordered

    respond_to do |format|
      format.html { redirect_to space_memories_path(@space) }
      format.md do
        content = generate_markdown_export(@memories)
        send_data content,
          filename: "#{@space.name.parameterize}-memories-#{Date.current}.md",
          type: "text/markdown",
          disposition: "attachment"
      end
      format.json do
        content = @memories.map { |m| export_memory_json(m) }
        send_data content.to_json,
          filename: "#{@space.name.parameterize}-memories-#{Date.current}.json",
          type: "application/json",
          disposition: "attachment"
      end
    end
  end

  # GET /spaces/:space_id/memories/:id/versions
  def versions
    @versions = @memory.versions.ordered
    @current_version = @memory.latest_version
  end

  # GET /spaces/:space_id/memories/:id/version?version_number=X
  def version
    @version_number = params[:version_number].to_i
    @version = @memory.versions.find_by(version_number: @version_number)

    unless @version
      redirect_to versions_space_memory_path(@space, @memory), alert: "Version not found."
      return
    end

    # Find the previous version for comparison
    @previous_version = @memory.versions
                               .where("version_number < ?", @version_number)
                               .order(version_number: :desc)
                               .first

    # Calculate diffs
    @title_changed = @previous_version && @version.title != @previous_version.title
    @content_changed = @previous_version && @version.content != @previous_version.content
    @type_changed = @previous_version && @version.memory_type != @previous_version.memory_type

    # Generate side-by-side diffs
    if @previous_version
      @title_diff = InlineDiff.side_by_side_diff(@previous_version.title, @version.title) if @title_changed
      @content_diff = InlineDiff.side_by_side_diff(@previous_version.content, @version.content) if @content_changed
    end
  end

  # POST /spaces/:space_id/memories/:id/restore_version
  def restore_version
    version_number = params[:version_number].to_i

    if version_number <= 0
      redirect_to versions_space_memory_path(@space, @memory), alert: "Invalid version number."
      return
    end

    version = @memory.versions.find_by(version_number: version_number)

    unless version
      redirect_to versions_space_memory_path(@space, @memory), alert: "Version not found."
      return
    end

    begin
      version.restore_to_memory!(
        Current.user,
        params[:reason].presence || "Restored by user"
      )
      redirect_to space_memory_path(@space, @memory), notice: "Memory restored to version #{version_number}."
    rescue => e
      Rails.logger.error "[MemoriesController] Restore failed: #{e.message}"
      redirect_to versions_space_memory_path(@space, @memory), alert: "Failed to restore: #{e.message}"
    end
  end

  private

  def set_space
    @space = Current.account.spaces.find(params[:space_id])
  end

  def set_memory
    @memory = @space.memories.find(params[:id])
  end

  def memory_params
    params.require(:memory).permit(:title, :content, :memory_type, :status, :position, metadata: {})
  end

  def generate_markdown_export(memories)
    lines = []
    lines << "# #{@space.name} - Memory Export"
    lines << ""
    lines << "Export Date: #{Date.current}"
    lines << "Total Memories: #{memories.count}"
    lines << ""
    lines << "---"
    lines << ""

    memories.group_by(&:memory_type).each do |type, type_memories|
      lines << "## #{type.humanize} (#{type_memories.count})"
      lines << ""

      type_memories.each do |memory|
        lines << "### #{memory.title}"
        lines << ""
        lines << "**Type:** #{memory.memory_type_display}"
        lines << "**Status:** #{memory.status_display}"
        lines << "**Created:** #{memory.created_at.strftime('%Y-%m-%d %H:%M')}"
        lines << "**Updated:** #{memory.updated_at.strftime('%Y-%m-%d %H:%M')}"
        lines << "**Source:** #{memory.source_display}" if memory.source.present?
        lines << ""
        lines << memory.content
        lines << ""
        lines << "---"
        lines << ""
      end
    end

    lines.join("\n")
  end

  def export_memory_json(memory)
    {
      id: memory.id,
      title: memory.title,
      content: memory.content,
      memory_type: memory.memory_type,
      status: memory.status,
      position: memory.position,
      metadata: memory.metadata,
      source_type: memory.source_type,
      source_id: memory.source_id,
      created_by: memory.creator_display,
      created_at: memory.created_at.iso8601,
      updated_at: memory.updated_at.iso8601
    }
  end
end
