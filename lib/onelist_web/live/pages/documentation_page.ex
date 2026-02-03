defmodule OnelistWeb.DocumentationPage do
  use OnelistWeb, :live_view

  alias OnelistWeb.{Navigation, Footer}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Onelist Documentation")
     |> assign(:current_user, nil)
     |> assign(:current_page, :documentation)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white">
      <.live_component
        module={Navigation}
        id="main-nav"
        current_user={@current_user}
        current_page={@current_page}
      />

      <div class="py-16 sm:py-24">
        <div class="mx-auto max-w-7xl px-6 lg:px-8">
          <div class="mx-auto max-w-3xl lg:mx-0">
            <h1
              class="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl"
              data-test-id="documentation-title"
            >
              Onelist Documentation
            </h1>
            <p class="mt-2 text-lg leading-8 text-gray-600">
              Learn how to get the most out of Onelist with our comprehensive documentation.
            </p>
          </div>

          <div class="mx-auto mt-10 max-w-3xl divide-y divide-gray-900/10">
            <!-- Getting Started Section -->
            <section class="py-10" data-test-id="getting-started-section">
              <h2 class="text-2xl font-bold tracking-tight text-gray-900">Getting Started</h2>
              <div class="mt-6 grid grid-cols-1 gap-8 sm:grid-cols-2">
                <div class="bg-white p-6 shadow rounded-lg">
                  <h3 class="text-lg font-medium text-gray-900">Creating an Account</h3>
                  <p class="mt-2 text-gray-600">
                    Sign up for a free account to start using Onelist. We offer various plans to fit your needs.
                  </p>
                  <a href={~p"/register"} class="mt-4 text-indigo-600 hover:text-indigo-500 block">
                    Sign up now →
                  </a>
                </div>
                <div class="bg-white p-6 shadow rounded-lg">
                  <h3 class="text-lg font-medium text-gray-900">Your First List</h3>
                  <p class="mt-2 text-gray-600">
                    Learn how to create your first list and add items to it. Organize your thoughts and tasks efficiently.
                  </p>
                </div>
              </div>
            </section>
            <!-- API Reference Section -->
            <section class="py-10" data-test-id="api-reference-section">
              <h2 class="text-2xl font-bold tracking-tight text-gray-900">API Reference</h2>
              <p class="mt-2 text-gray-600">
                Onelist provides a comprehensive API for integrating with your applications.
              </p>

              <div class="mt-6 overflow-hidden">
                <div class="bg-gray-50 p-4 rounded-md">
                  <pre class="overflow-x-auto text-sm">
                    <code>
                      # Example API request
                      curl -X GET "https://api.onelist.com/v1/lists" \\
                        -H "Authorization: Bearer YOUR_API_KEY" \\
                        -H "Content-Type: application/json"
                    </code>
                  </pre>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="text-lg font-medium text-gray-900">Authentication</h3>
                <p class="mt-2 text-gray-600">
                  All API requests require authentication using an API key. You can generate an API key from your account settings.
                </p>
              </div>

              <div class="mt-6">
                <h3 class="text-lg font-medium text-gray-900">Rate Limiting</h3>
                <p class="mt-2 text-gray-600">
                  API requests are rate-limited to ensure fair usage. The rate limits vary by plan.
                </p>
              </div>
            </section>
            <!-- Examples Section -->
            <section class="py-10" data-test-id="examples-section">
              <h2 class="text-2xl font-bold tracking-tight text-gray-900">Examples</h2>

              <div class="mt-6">
                <h3 class="text-lg font-medium text-gray-900">Task Management</h3>
                <p class="mt-2 text-gray-600">
                  Learn how to use Onelist for effective task management and productivity.
                </p>

                <div class="mt-4 bg-white p-6 shadow rounded-lg">
                  <ul class="list-disc pl-5 space-y-2">
                    <li>Create a daily to-do list</li>
                    <li>Set priorities for tasks</li>
                    <li>Track completion status</li>
                    <li>Set due dates and reminders</li>
                  </ul>
                </div>
              </div>

              <div class="mt-6">
                <h3 class="text-lg font-medium text-gray-900">Note Taking</h3>
                <p class="mt-2 text-gray-600">
                  Discover how to use Onelist for organizing your notes and ideas.
                </p>

                <div class="mt-4 bg-white p-6 shadow rounded-lg">
                  <p class="text-gray-700">
                    Onelist supports rich Markdown formatting for your notes:
                  </p>
                  <div class="mt-4 bg-gray-50 p-4 rounded-md">
                    <pre class="overflow-x-auto text-sm">
                      <code>
                        # Heading 1
                        ## Heading 2
                        
                        - Bullet point
                        - Another point
                        
                        1. Numbered item
                        2. Another item
                        
                        **Bold text** and *italic text*
                        
                        [Link text](https://example.com)
                      </code>
                    </pre>
                  </div>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>

      <.live_component module={Footer} id="main-footer" />
    </div>
    """
  end
end
